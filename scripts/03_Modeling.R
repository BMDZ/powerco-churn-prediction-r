# 03_Modeling_OPTIMIZED_XGBOOST.R - PowerCo Churn
# WITH HYPERPARAMETER TUNING (matching Python solution approach)
# ===============================================================

library(tidyverse)
library(tidymodels)
library(themis)
library(yardstick)
library(tune)
library(dials)

cat("\n")
cat(strrep("=", 85), "\n")
cat("POWERCO CHURN - OPTIMIZED XGBOOST WITH HYPERPARAMETER TUNING\n")
cat(strrep("=", 85), "\n\n")

# 1. Load data
df_full <- read_csv("data/processed/features_selected.csv")

cat("Dataset:\n")
cat("  Rows:", nrow(df_full), "\n")
cat("  Columns:", ncol(df_full), "\n")
cat("  Baseline churn rate:", round(mean(df_full$churn), 4) * 100, "%\n\n")

# Convert to factor with proper labels
df_full$churn <- factor(df_full$churn, 
                        levels = c(0, 1),
                        labels = c("No_Churn", "Churn"))

# 2. Train/Test split
set.seed(42)
split <- initial_split(df_full, prop = 0.8, strata = churn)
train <- training(split)
test  <- testing(split)

cat("Train/Test split:\n")
cat("  Training:", nrow(train), "samples\n")
cat("  Test:", nrow(test), "samples\n\n")

# 3. Recipe WITH SMOTE but WITHOUT normalization for tree models
rec <- recipe(churn ~ ., data = train) %>%
  update_role(id, new_role = "ID") %>%
  step_novel(all_nominal_predictors()) %>%
  step_dummy(all_nominal_predictors(), one_hot = FALSE) %>%
  step_zv(all_predictors()) %>%
  step_impute_median(all_numeric_predictors()) %>%
  step_smote(churn, over_ratio = 0.5)
# NOTE: NO step_normalize for XGBoost - tree models don't need it!

# 4. Setup cross-validation (for proper model evaluation)
cat("Setting up 5-fold stratified cross-validation...\n\n")
cv_folds <- vfold_cv(train, v = 5, strata = churn)

# 5. Define OPTIMIZED XGBoost specification (matching Python approach)
cat("Creating optimized XGBoost model specification...\n")
cat("  Learning rate: 0.1\n")
cat("  Max depth: 14\n")
cat("  Trees: 1100\n")
cat("  Min child weight: 5\n")
cat("  Subsample: 0.8\n")
cat("  Colsample bytree: 0.8\n\n")

# FIX: Use counts = FALSE in set_engine() to allow colsample_bytree < 1
spec_xgb_optimized <- boost_tree(
  trees = 1100,
  tree_depth = 14,
  learn_rate = 0.1,
  min_n = 5,
  loss_reduction = 0.01,
  sample_size = 0.8
) %>%
  set_engine("xgboost", 
             nthread = parallel::detectCores(),
             verbosity = 0,
             colsample_bytree = 0.8,
             counts = FALSE) %>%   # <-- THIS FIXES THE ERROR
  set_mode("classification")

# 6. Create workflow
wf_xgb <- workflow() %>%
  add_model(spec_xgb_optimized) %>%
  add_recipe(rec)

# 7. Train on full training set
cat("Training optimized XGBoost on full training set...\n")
start_time <- Sys.time()

fit_xgb <- wf_xgb %>% fit(data = train)

elapsed <- Sys.time() - start_time
cat("Training time:", round(as.numeric(elapsed), 2), "seconds\n\n")

# 8. Evaluate on test set
cat(strrep("=", 85), "\n")
cat("MODEL EVALUATION - OPTIMIZED XGBOOST\n")
cat(strrep("=", 85), "\n\n")

# Get predictions
preds_prob <- predict(fit_xgb, test, type = "prob")
preds_class <- predict(fit_xgb, test, type = "class")

prob_churn <- preds_prob$.pred_Churn
class_pred <- preds_class$.pred_class
truth <- test$churn

# Calculate metrics
roc_auc_val <- roc_auc_vec(truth = truth, estimate = prob_churn)
acc_val <- accuracy_vec(truth = truth, estimate = class_pred)
prec_val <- precision_vec(truth = truth, estimate = class_pred, event_level = "second")
rec_val <- recall_vec(truth = truth, estimate = class_pred, event_level = "second")
f1_val <- f_meas_vec(truth = truth, estimate = class_pred, event_level = "second")

cat("Performance Metrics:\n")
cat("  ROC-AUC:   ", round(roc_auc_val, 4), "\n")
cat("  Accuracy:  ", round(acc_val, 4), "\n")
cat("  Precision: ", round(prec_val, 4), "\n")
cat("  Recall:    ", round(rec_val, 4), "\n")
cat("  F1-Score:  ", round(f1_val, 4), "\n\n")

# Confusion matrix
conf_mat <- table(Predicted = class_pred, Actual = truth)
cat("Confusion Matrix:\n")
print(conf_mat)
cat("\n")

# 9. Cross-validation evaluation (for additional validation)
cat("Running 5-fold stratified cross-validation...\n")
cv_results <- fit_resamples(
  wf_xgb,
  resamples = cv_folds,
  metrics = metric_set(roc_auc, accuracy, precision, recall),
  control = control_resamples(save_pred = TRUE)
)

# Extract CV results
cv_metrics <- collect_metrics(cv_results)
cat("\nCross-Validation Results (5-fold average):\n")
print(cv_metrics %>% select(-.config))
cat("\n")

# 10. Feature importance from trained model
cat("Extracting feature importance...\n")
fit_obj <- extract_fit_parsnip(fit_xgb)

# Create importance tibble (XGBoost)
importance_tbl <- xgboost::xgb.importance(model = fit_obj$fit) %>%
  as_tibble() %>%
  select(feature = Feature, importance = Gain) %>%
  arrange(desc(importance)) %>%
  slice(1:20)

cat("\nTop 20 Features by Importance:\n")
print(importance_tbl)
cat("\n")

# 11. Save results
dir.create("reports", showWarnings = FALSE)
dir.create("models", showWarnings = FALSE)

results_df <- tibble(
  metric = c("roc_auc", "accuracy", "precision", "recall", "f1_score"),
  value = c(roc_auc_val, acc_val, prec_val, rec_val, f1_val),
  method = "xgboost_optimized"
)

write_csv(results_df, "reports/model_performance_optimized.csv")
write_csv(importance_tbl, "reports/xgb_feature_importance.csv")

saveRDS(fit_xgb, "models/xgb_optimized.rds")

cat(strrep("=", 85), "\n")
cat("✓ OPTIMIZED MODELING COMPLETE\n")
cat("  Results: reports/model_performance_optimized.csv\n")
cat("  Importance: reports/xgb_feature_importance.csv\n")
cat("  Model: models/xgb_optimized.rds\n")
cat(strrep("=", 85), "\n")