# 05_Business_Analysis.R - PowerCo Churn
# Financial Impact Analysis and Retention Strategy ROI
# ====================================================================

library(tidyverse)
library(tidymodels)

cat("\n")
cat(strrep("=", 85), "\n")
cat("BUSINESS ANALYSIS - RETENTION STRATEGY ROI CALCULATION\n")
cat(strrep("=", 85), "\n\n")

# 1. Load data and predictions
cat("Loading customer data and predictions...\n\n")

df_full <- read_csv("data/processed/features_selected.csv")
df_full$churn <- factor(df_full$churn, levels = c(0, 1), 
                        labels = c("No_Churn", "Churn"))

set.seed(42)
split <- initial_split(df_full, prop = 0.8, strata = churn)
train <- training(split)
test <- testing(split)

# Load final model
final_model <- readRDS("models/xgb_optimized.rds")

# Get predictions
test_preds_prob <- predict(final_model, test, type = "prob")$.pred_Churn

pred_data <- test %>%
  select(id, churn) %>%
  mutate(
    predicted_churn_prob = test_preds_prob,
    actual_churn = as.numeric(churn) - 1
  )

# 2. CALCULATE BASELINE REVENUE
cat(strrep("=", 85), "\n")
cat("REVENUE BASELINE CALCULATION\n")
cat(strrep("=", 85), "\n\n")

# Get original features for revenue calculation
train_orig <- read_csv("ml_case_training_data.csv")
hist_orig <- read_csv("ml_case_training_hist_data.csv")

# Calculate average metrics from training set
avg_consumption_12m <- mean(train_orig$cons_12m, na.rm = TRUE)
avg_consumption_gas_12m <- mean(train_orig$cons_gas_12m, na.rm = TRUE)
avg_price_electricity <- mean(hist_orig$price_p1_fix, na.rm = TRUE)
avg_price_gas <- mean(hist_orig$price_p2_fix, na.rm = TRUE)
avg_meter_rent_monthly <- 70.3  # From EDA
months_per_year <- 12

# Annual revenue per customer (baseline)
baseline_annual_revenue_per_customer <- 
  (avg_consumption_12m * avg_price_electricity) +
  (avg_consumption_gas_12m * avg_price_gas) +
  (avg_meter_rent_monthly * months_per_year)

cat("Revenue Baseline Assumptions:\n")
cat("  Electricity consumption (12m):", round(avg_consumption_12m, 0), "units\n")
cat("  Gas consumption (12m):        ", round(avg_consumption_gas_12m, 0), "units\n")
cat("  Electricity price:            ", round(avg_price_electricity, 2), "€/unit\n")
cat("  Gas price:                    ", round(avg_price_gas, 2), "€/unit\n")
cat("  Meter rent (annual):          ", round(avg_meter_rent_monthly * 12, 0), "€\n")
cat("  BASELINE ANNUAL REVENUE:      ", 
    round(baseline_annual_revenue_per_customer, 0), "€\n\n")

# 3. BUSINESS ASSUMPTIONS
cat(strrep("=", 85), "\n")
cat("BUSINESS ASSUMPTIONS\n")
cat(strrep("=", 85), "\n\n")

# Churn assumptions
churn_revenue_loss_rate <- 0.919  # Customers lose 91.9% of revenue when they churn
discount_offered <- 0.15          # 15% discount to retention offer
retention_success_rate <- 0.50    # 50% of offers succeed in preventing churn
retention_campaign_cost <- 50     # €50 cost per contact (email, SMS, etc.)

cat("Retention Campaign Assumptions:\n")
cat("  Revenue loss from churn:      ", churn_revenue_loss_rate * 100, "%\n")
cat("  Discount offered:             ", discount_offered * 100, "%\n")
cat("  Retention success rate:       ", retention_success_rate * 100, "%\n")
cat("  Campaign cost per customer:   ", retention_campaign_cost, "€\n\n")

# 4. SCENARIO ANALYSIS - DIFFERENT THRESHOLDS
cat(strrep("=", 85), "\n")
cat("SCENARIO ANALYSIS: ROI BY TARGETING THRESHOLD\n")
cat(strrep("=", 85), "\n\n")

thresholds <- c(0.15, 0.20, 0.25, 0.30, 0.35, 0.40)
scenario_results <- tibble()

for (threshold in thresholds) {
  
  # Target customers above threshold
  targeted <- pred_data %>%
    filter(predicted_churn_prob >= threshold)
  
  n_targeted <- nrow(targeted)
  n_actual_churners <- sum(targeted$actual_churn)
  
  # Calculate financial impact
  campaign_cost_total <- n_targeted * retention_campaign_cost
  
  # Revenue saved from successful retention
  revenue_saved_per_customer <- baseline_annual_revenue_per_customer * churn_revenue_loss_rate
  
  # Expected saved revenue = (# targeted) × (success rate) × (revenue loss prevented)
  expected_saved_revenue <- 
    n_actual_churners * retention_success_rate * revenue_saved_per_customer
  
  # Revenue lost from discount on retained customers
  # (# targeted) × (success rate) × (annual revenue) × (discount %)
  discount_cost <- 
    n_targeted * retention_success_rate * baseline_annual_revenue_per_customer * discount_offered
  
  # Net benefit
  net_benefit <- expected_saved_revenue - discount_cost - campaign_cost_total
  
  # ROI
  roi <- ifelse(campaign_cost_total > 0, 
                (net_benefit / campaign_cost_total) * 100, 
                0)
  
  # Precision on actual churners
  precision <- ifelse(n_targeted > 0, n_actual_churners / n_targeted, 0)
  
  scenario_results <- bind_rows(scenario_results, tibble(
    Threshold = threshold,
    Customers_Targeted = n_targeted,
    Actual_Churners_in_Target = n_actual_churners,
    Precision = precision,
    Campaign_Cost = campaign_cost_total,
    Expected_Revenue_Saved = expected_saved_revenue,
    Discount_Cost = discount_cost,
    Net_Benefit = net_benefit,
    ROI_Percent = roi
  ))
}

cat("Financial Impact by Targeting Threshold:\n\n")
print(scenario_results %>%
        mutate(
          Campaign_Cost = round(Campaign_Cost, 0),
          Expected_Revenue_Saved = round(Expected_Revenue_Saved, 0),
          Discount_Cost = round(Discount_Cost, 0),
          Net_Benefit = round(Net_Benefit, 0),
          ROI_Percent = round(ROI_Percent, 1),
          Precision = round(Precision, 2)
        ))

cat("\n")

# 5. OPTIMAL STRATEGY RECOMMENDATION
optimal_row <- scenario_results %>%
  filter(Net_Benefit == max(Net_Benefit)) %>%
  slice(1)

cat(strrep("=", 85), "\n")
cat("RECOMMENDED RETENTION STRATEGY\n")
cat(strrep("=", 85), "\n\n")

cat("OPTIMAL THRESHOLD:", optimal_row$Threshold, "\n\n")
cat("Financial Projections:\n")
cat("  Customers to target:          ", round(optimal_row$Customers_Targeted, 0), "\n")
cat("  Actual churners in target:    ", round(optimal_row$Actual_Churners_in_Target, 0), "\n")
cat("  Targeting precision:          ", round(optimal_row$Precision, 3) * 100, "%\n\n")

cat("Campaign Economics:\n")
cat("  Total campaign cost:          €", round(optimal_row$Campaign_Cost, 0), "\n")
cat("  Expected revenue saved:       €", round(optimal_row$Expected_Revenue_Saved, 0), "\n")
cat("  Discount cost (retained):     €", round(optimal_row$Discount_Cost, 0), "\n")
cat("  NET BENEFIT:                  €", round(optimal_row$Net_Benefit, 0), "\n")
cat("  ROI:                          ", round(optimal_row$ROI_Percent, 1), "%\n\n")

# 6. RISK SEGMENT STRATEGY
cat(strrep("=", 85), "\n")
cat("SEGMENTED RETENTION STRATEGY\n")
cat(strrep("=", 85), "\n")
cat("(Customize offers by risk segment)\n\n")

# Define risk segments
segment_strategy <- pred_data %>%
  mutate(
    Risk_Segment = case_when(
      predicted_churn_prob < 0.15 ~ "Low Risk",
      predicted_churn_prob < 0.30 ~ "Medium Risk",
      predicted_churn_prob < 0.50 ~ "High Risk",
      TRUE ~ "Very High Risk"
    )
  ) %>%
  group_by(Risk_Segment) %>%
  summarise(
    Count = n(),
    Actual_Churn_Rate = mean(actual_churn),
    Avg_Churn_Prob = mean(predicted_churn_prob),
    .groups = "drop"
  ) %>%
  mutate(
    Discount_Strategy = case_when(
      Risk_Segment == "Low Risk" ~ "0% (Maintain satisfaction)",
      Risk_Segment == "Medium Risk" ~ "5-8% (Value retention)",
      Risk_Segment == "High Risk" ~ "10-15% (Strategic offer)",
      TRUE ~ "15-25% (Urgent save)"
    ),
    Campaign_Focus = case_when(
      Risk_Segment == "Low Risk" ~ "Satisfaction surveys",
      Risk_Segment == "Medium Risk" ~ "Personalized offers",
      Risk_Segment == "High Risk" ~ "Manager outreach",
      TRUE ~ "Executive escalation"
    )
  )

print(segment_strategy %>%
        mutate(
          Actual_Churn_Rate = round(Actual_Churn_Rate * 100, 1),
          Avg_Churn_Prob = round(Avg_Churn_Prob, 2)
        ))

cat("\n")

# 7. EXPECTED OUTCOMES
cat(strrep("=", 85), "\n")
cat("EXPECTED ANNUAL OUTCOMES (based on recommendations)\n")
cat(strrep("=", 85), "\n\n")

# Apply optimal strategy to full customer base
# Scale from test set proportions to full base
test_size <- nrow(pred_data)
estimated_full_customer_base <- 16096

churn_rate_baseline <- mean(pred_data$actual_churn)
expected_churners_full <- estimated_full_customer_base * churn_rate_baseline

campaign_cost_full <- optimal_row$Customers_Targeted * (estimated_full_customer_base / test_size) * 
  retention_campaign_cost

revenue_saved_full <- optimal_row$Actual_Churners_in_Target * (estimated_full_customer_base / test_size) *
  retention_success_rate * revenue_saved_per_customer

discount_cost_full <- optimal_row$Customers_Targeted * (estimated_full_customer_base / test_size) *
  retention_success_rate * baseline_annual_revenue_per_customer * discount_offered

net_benefit_full <- revenue_saved_full - discount_cost_full - campaign_cost_full

cat("Full Customer Base Projection:\n")
cat("  Estimated customers:         ", estimated_full_customer_base, "\n")
cat("  Expected churners (baseline):", round(expected_churners_full, 0), "\n")
cat("  Churn rate baseline:         ", round(churn_rate_baseline * 100, 2), "%\n\n")

cat("Annual Campaign Impact:\n")
cat("  Customers targeted:          ", round(optimal_row$Customers_Targeted * (estimated_full_customer_base / test_size), 0), "\n")
cat("  Total campaign cost:         €", round(campaign_cost_full, 0), "\n")
cat("  Expected revenue saved:      €", round(revenue_saved_full, 0), "\n")
cat("  Discount cost:               €", round(discount_cost_full, 0), "\n")
cat("  NET ANNUAL BENEFIT:          €", round(net_benefit_full, 0), "\n")
cat("  Expected ROI:                ", round((net_benefit_full / campaign_cost_full) * 100, 1), "%\n\n")

# 8. SAVE RESULTS
write_csv(scenario_results, "reports/business_roi_scenarios.csv")
write_csv(segment_strategy, "reports/segmented_retention_strategy.csv")

# Summary report
business_summary <- tibble(
  Metric = c(
    "Baseline Annual Revenue per Customer",
    "Annual Revenue Lost per Churned Customer",
    "Recommended Targeting Threshold",
    "Customers to Target (test set)",
    "Campaign Cost per Customer",
    "Expected Annual Net Benefit (test set)",
    "Expected ROI",
    "Estimated Annual Benefit (full base)"
  ),
  Value = c(
    round(baseline_annual_revenue_per_customer, 0),
    round(revenue_saved_per_customer, 0),
    optimal_row$Threshold,
    round(optimal_row$Customers_Targeted, 0),
    retention_campaign_cost,
    round(optimal_row$Net_Benefit, 0),
    round(optimal_row$ROI_Percent, 1),
    round(net_benefit_full, 0)
  ),
  Unit = c("€", "€", "", "customers", "€", "€", "%", "€")
)

write_csv(business_summary, "reports/business_analysis_summary.csv")

cat(strrep("=", 85), "\n")
cat("✓ BUSINESS ANALYSIS COMPLETE\n")
cat(strrep("=", 85), "\n\n")

cat("Generated Outputs:\n")
cat("  1. business_roi_scenarios.csv - ROI at different thresholds\n")
cat("  2. segmented_retention_strategy.csv - Strategy by risk segment\n")
cat("  3. business_analysis_summary.csv - Key metrics summary\n\n")

cat("Key Recommendations:\n")
cat("  • Use threshold", optimal_row$Threshold, "for customer targeting\n")
cat("  • Expected annual benefit: €", round(net_benefit_full, 0), "\n")
cat("  • ROI on retention investment: ", round((net_benefit_full / campaign_cost_full) * 100, 1), "%\n")
cat("  • Implement segmented offers by risk level\n\n")

cat(strrep("=", 85), "\n")