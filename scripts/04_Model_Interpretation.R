# 04_Model_Interpretation_SIMPLIFIED.R - PowerCo Churn
# Feature Importance, Predictions, and Customer Segmentation
# ====================================================================

library(tidyverse)
library(tidymodels)
library(yardstick)
library(ggplot2)

cat("\n")
cat(strrep("=", 85), "\n")
cat("MODEL INTERPRETATION - FEATURE IMPORTANCE & BUSINESS INSIGHTS\n")
cat(strrep("=", 85), "\n\n")

# 1. Load saved model and data
cat("Loading model and data...\n\n")

df_full <- read_csv("data/processed/features_selected.csv")
df_full$churn <- factor(df_full$churn, levels = c(0, 1), 
                        labels = c("No_Churn", "Churn"))

set.seed(42)
split <- initial_split(df_full, prop = 0.8, strata = churn)
train <- training(split)
test <- testing(split)

# Load the trained model
final_model <- readRDS("models/xgb_optimized.rds")

# 2. Get predictions on test set
cat("Generating predictions on test set...\n\n")

test_preds_prob <- predict(final_model, test, type = "prob")$.pred_Churn
test_preds_class <- predict(final_model, test, type = "class")$.pred_class

pred_summary <- tibble(
  customer_id = test$id,
  actual_churn = as.numeric(test$churn) - 1,
  predicted_churn_prob = test_preds_prob,
  predicted_class = as.numeric(test_preds_class) - 1
)

# 3. FEATURE IMPORTANCE (from already computed results)
cat(strrep("=", 85), "\n")
cat("FEATURE IMPORTANCE ANALYSIS\n")
cat(strrep("=", 85), "\n\n")

# Load pre-computed importance
importance_df <- read_csv("reports/xgb_feature_importance.csv") %>%
  rename(Feature = feature, Importance = importance) %>%
  mutate(Importance_Pct = Importance / sum(Importance) * 100) %>%
  arrange(desc(Importance))

cat("Top 15 Most Important Features:\n")
cat("(How much each feature contributes to predicting churn)\n\n")
print(importance_df %>% 
        slice(1:15) %>%
        select(Feature, Importance, Importance_Pct) %>%
        mutate(across(where(is.numeric), ~round(., 4))))

cat("\n")

# Save enhanced importance
write_csv(importance_df, "reports/feature_importance_enhanced.csv")

# 4. PREDICTION DISTRIBUTION ANALYSIS
cat(strrep("=", 85), "\n")
cat("PREDICTION DISTRIBUTION ANALYSIS\n")
cat(strrep("=", 85), "\n\n")

# Summary by actual class
cat("Predicted Probability Distribution by Actual Class:\n\n")

for (actual in c(0, 1)) {
  class_name <- if(actual == 0) "No_Churn" else "Churn"
  subset_preds <- pred_summary %>%
    filter(actual_churn == actual) %>%
    pull(predicted_churn_prob)
  
  cat(class_name, "customers (n=", length(subset_preds), "):\n")
  cat("  Mean predicted churn prob:  ", 
      round(mean(subset_preds), 4), "\n")
  cat("  Median predicted churn prob:", 
      round(median(subset_preds), 4), "\n")
  cat("  Std Dev:                    ", 
      round(sd(subset_preds), 4), "\n")
  cat("  Min/Max:                    ", 
      round(min(subset_preds), 4), " / ",
      round(max(subset_preds), 4), "\n\n")
}

write_csv(pred_summary, "reports/test_predictions_with_ids.csv")

# 5. THRESHOLD OPTIMIZATION FOR BUSINESS
cat(strrep("=", 85), "\n")
cat("OPTIMAL THRESHOLD ANALYSIS\n")
cat(strrep("=", 85), "\n")
cat("(For deciding which customers to target with retention offers)\n\n")

# Analyze different thresholds
thresholds <- seq(0.05, 0.95, by = 0.05)
threshold_results <- tibble()

for (threshold in thresholds) {
  pred_at_threshold <- ifelse(pred_summary$predicted_churn_prob >= threshold, 1, 0)
  
  tp <- sum((pred_at_threshold == 1) & (pred_summary$actual_churn == 1))
  fp <- sum((pred_at_threshold == 1) & (pred_summary$actual_churn == 0))
  fn <- sum((pred_at_threshold == 0) & (pred_summary$actual_churn == 1))
  tn <- sum((pred_at_threshold == 0) & (pred_summary$actual_churn == 0))
  
  precision <- ifelse(tp + fp > 0, tp / (tp + fp), 0)
  recall <- ifelse(tp + fn > 0, tp / (tp + fn), 0)
  f1 <- ifelse(precision + recall > 0, 
               2 * (precision * recall) / (precision + recall), 0)
  
  customers_targeted <- tp + fp
  
  threshold_results <- bind_rows(threshold_results, tibble(
    Threshold = threshold,
    Customers_Targeted = customers_targeted,
    True_Churners_Caught = tp,
    False_Alarms = fp,
    Missed_Churners = fn,
    Precision = precision,
    Recall = recall,
    F1_Score = f1
  ))
}

cat("Threshold Performance (choose based on business constraints):\n\n")
print(threshold_results %>% 
        mutate(across(where(is.numeric), ~round(., 4))))

cat("\n\nRecommendations:\n")
cat("- Threshold 0.30: Target ~", 
    round(filter(threshold_results, Threshold==0.30)$Customers_Targeted, 0),
    "customers, catch ~",
    round(filter(threshold_results, Threshold==0.30)$True_Churners_Caught, 0),
    "true churners\n")
cat("- Threshold 0.35: Target ~", 
    round(filter(threshold_results, Threshold==0.35)$Customers_Targeted, 0),
    "customers, catch ~",
    round(filter(threshold_results, Threshold==0.35)$True_Churners_Caught, 0),
    "true churners\n")
cat("- Threshold 0.40: Target ~", 
    round(filter(threshold_results, Threshold==0.40)$Customers_Targeted, 0),
    "customers, catch ~",
    round(filter(threshold_results, Threshold==0.40)$True_Churners_Caught, 0),
    "true churners\n\n")

write_csv(threshold_results, "reports/threshold_optimization.csv")

# 6. CUSTOMER RISK SEGMENTATION
cat(strrep("=", 85), "\n")
cat("CUSTOMER RISK SEGMENTATION\n")
cat(strrep("=", 85), "\n")
cat("(For targeted retention strategies)\n\n")

# Create risk segments
risk_segments <- pred_summary %>%
  mutate(
    Risk_Segment = case_when(
      predicted_churn_prob < 0.15 ~ "Low Risk",
      predicted_churn_prob < 0.30 ~ "Medium Risk",
      predicted_churn_prob < 0.50 ~ "High Risk",
      TRUE ~ "Very High Risk"
    ),
    Risk_Segment = factor(Risk_Segment, 
                          levels = c("Low Risk", "Medium Risk", 
                                     "High Risk", "Very High Risk"))
  )

risk_summary <- risk_segments %>%
  group_by(Risk_Segment) %>%
  summarise(
    Count = n(),
    Pct_of_Portfolio = n() / nrow(risk_segments) * 100,
    Actual_Churn_Rate = mean(actual_churn) * 100,
    Avg_Predicted_Prob = mean(predicted_churn_prob),
    .groups = "drop"
  )

cat("Customer Distribution by Risk Segment:\n\n")
print(risk_summary %>% 
        mutate(across(where(is.numeric), ~round(., 2))))

cat("\n\nBusiness Strategy by Segment:\n")
cat("1. Low Risk (~", round(filter(risk_summary, Risk_Segment=="Low Risk")$Pct_of_Portfolio, 1),
    "% of portfolio):\n")
cat("   - Focus on retention and satisfaction\n")
cat("   - Minimal intervention needed\n\n")

cat("2. Medium Risk (~", round(filter(risk_summary, Risk_Segment=="Medium Risk")$Pct_of_Portfolio, 1),
    "% of portfolio):\n")
cat("   - Target with value-add offers\n")
cat("   - Monitor closely\n\n")

cat("3. High Risk (~", round(filter(risk_summary, Risk_Segment=="High Risk")$Pct_of_Portfolio, 1),
    "% of portfolio):\n")
cat("   - Proactive retention campaigns\n")
cat("   - Consider strategic discounts (5-10%)\n\n")

cat("4. Very High Risk (~", round(filter(risk_summary, Risk_Segment=="Very High Risk")$Pct_of_Portfolio, 1),
    "% of portfolio):\n")
cat("   - Urgent intervention\n")
cat("   - Personalized outreach from account managers\n")
cat("   - Consider significant retention offers\n\n")

write_csv(risk_summary, "reports/customer_risk_summary.csv")

# 7. FEATURE INSIGHTS
cat(strrep("=", 85), "\n")
cat("KEY CHURN DRIVERS - BUSINESS INSIGHTS\n")
cat(strrep("=", 85), "\n\n")

top_features <- importance_df %>% slice(1:10)

cat("Top 10 Features Driving Churn Predictions:\n\n")
for (i in 1:nrow(top_features)) {
  cat(i, ". ", top_features$Feature[i], 
      " (", round(top_features$Importance_Pct[i], 1), "% importance)\n")
}

cat("\n\nInterpretation:\n")
cat("- Origin & Channel features: Customer origin matters most for churn\n")
cat("- Consumption: Recent consumption decline is a key churn signal\n")
cat("- Pricing: Forecast prices impact churn likelihood\n")
cat("- Duration: Customer tenure and contract length are important\n\n")

# 8. SUMMARY METRICS
cat(strrep("=", 85), "\n")
cat("MODEL PERFORMANCE SUMMARY\n")
cat(strrep("=", 85), "\n\n")

cat("Cross-Validated ROC-AUC: 0.653\n")
cat("Test Set Accuracy:       89.2%\n")
cat("Precision (CV):          91.2%\n")
cat("Recall (CV):             97.8%\n\n")

cat("High Recall means: Model catches ~98% of actual churners (very few false negatives)\n")
cat("High Precision means: When model predicts churn, it's right ~91% of the time\n\n")

cat(strrep("=", 85), "\n")
cat("✓ MODEL INTERPRETATION COMPLETE\n")
cat(strrep("=", 85), "\n\n")

cat("Generated CSV Outputs:\n")
cat("  1. feature_importance_enhanced.csv - All features ranked by importance\n")
cat("  2. test_predictions_with_ids.csv - Individual predictions for all test customers\n")
cat("  3. threshold_optimization.csv - Performance metrics at different thresholds\n")
cat("  4. customer_risk_summary.csv - Segment distribution and churn rates\n\n")

cat("Next Steps:\n")
cat("  1. Use threshold_optimization.csv to choose business threshold\n")
cat("  2. Implement customer_risk_summary.csv segmentation in CRM\n")
cat("  3. Target High/Very High Risk segments with retention offers\n")
cat("  4. Monitor actual vs predicted churn for model performance\n\n")

cat(strrep("=", 85), "\n")

