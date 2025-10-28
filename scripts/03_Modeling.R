#!/usr/bin/env Rscript
# 03_Modeling.R - PowerCo Customer Churn Prediction
# Model Training and Evaluation
# =================================================

library(tidyverse)
library(tidymodels)
library(themis)
library(magrittr)

# 1. Load engineered features -----------------------------------------------
df_full <- read_csv("data/processed/features_selected.csv")
df_full$churn <- as.factor(df_full$churn)

# 2. Split into train and test sets -----------------------------------------
set.seed(42)
split <- initial_split(df_full, prop = 0.8, strata = churn)
train <- training(split)
test  <- testing(split)

cat("Training samples:", nrow(train), "Test samples:", nrow(test), "\n")

# 3. Create recipe ----------------------------------------------------------
rec <- recipe(churn ~ ., data = train) %>%
  update_role(id, new_role = "ID") %>%                 # mark id as ID
  step_novel(all_nominal_predictors()) %>%             # handle new levels
  step_dummy(all_nominal_predictors(), one_hot = FALSE) %>%
  step_zv(all_predictors()) %>%                        # remove zero variance predictors
  step_impute_median(all_numeric_predictors()) %>%
  step_normalize(all_numeric_predictors())

# 4. Define model specs ------------------------------------------------------
specs <- list(
  lr  = logistic_reg() %>% set_engine("glm"),
  rf  = rand_forest(trees = 300, min_n = 10) %>% 
    set_engine("ranger", num.threads = parallel::detectCores()) %>% 
    set_mode("classification"),
  xgb = boost_tree(trees = 300, tree_depth = 6, learn_rate = 0.05) %>% 
    set_engine("xgboost", nthread = parallel::detectCores()) %>% 
    set_mode("classification")
)

# 5. Fit models -------------------------------------------------------------
fits <- purrr::imap(
  specs,
  ~ workflow() %>% add_model(.x) %>% add_recipe(rec) %>% fit(data = train)
)

# 6. Evaluate models --------------------------------------------------------
yte <- test$churn

res <- purrr::map_df(fits, function(wf) {
  pr <- predict(wf, test, type = "prob") %>% pull(.pred_1)
  prc <- ifelse(pr >= 0.35, 1, 0)
  prc <- factor(prc, levels = levels(yte))
  tibble(
    roc  = roc_auc_vec(yte, pr),
    acc  = accuracy_vec(yte, prc),
    prec = precision_vec(yte, prc),
    rec  = recall_vec(yte, prc),
    f1   = f_meas_vec(yte, prc)
  )
}, .id = "model")

print(res)

# 7. Save models ------------------------------------------------------------
if(!dir.exists("models")) dir.create("models")
purrr::walk2(fits, names(fits), ~saveRDS(.x, file.path("models", paste0(.y, ".rds"))))

cat("✓ Models saved in models/ directory.\n")

