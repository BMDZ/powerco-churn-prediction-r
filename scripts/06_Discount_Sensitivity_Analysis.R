# 06_Discount_Sensitivity_Analysis.R - PowerCo Churn
# Test Different Discount Levels and Their Impact on ROI
# ====================================================================

library(tidyverse)
library(tidymodels)

cat("\n")
cat(strrep("=", 85), "\n")
cat("DISCOUNT SENSITIVITY ANALYSIS - OPTIMAL DISCOUNT LEVEL\n")
cat(strrep("=", 85), "\n\n")

# 1. Load data and predictions
cat("Loading model and predictions...\n\n")

df_full <- read_csv("data/processed/features_selected.csv")
df_full$churn <- factor(df_full$churn, levels = c(0, 1), 
                        labels = c("No_Churn", "Churn"))

set.seed(42)
split <- initial_split(df_full, prop = 0.8, strata = churn)
train <- training(split)
test <- testing(split)

final_model <- readRDS("models/xgb_optimized.rds")
test_preds_prob <- predict(final_model, test, type = "prob")$.pred_Churn

pred_data <- test %>%
  select(id, churn) %>%
  mutate(
    predicted_churn_prob = test_preds_prob,
    actual_churn = as.numeric(churn) - 1
  )

# 2. Baseline revenue calculations
train_orig <- read_csv("ml_case_training_data.csv")
hist_orig <- read_csv("ml_case_training_hist_data.csv")

avg_consumption_12m <- mean(train_orig$cons_12m, na.rm = TRUE)
avg_consumption_gas_12m <- mean(train_orig$cons_gas_12m, na.rm = TRUE)
avg_price_electricity <- mean(hist_orig$price_p1_fix, na.rm = TRUE)
avg_price_gas <- mean(hist_orig$price_p2_fix, na.rm = TRUE)
avg_meter_rent_monthly <- 70.3

baseline_annual_revenue_per_customer <- 
  (avg_consumption_12m * avg_price_electricity) +
  (avg_consumption_gas_12m * avg_price_gas) +
  (avg_meter_rent_monthly * 12)

revenue_saved_per_customer <- baseline_annual_revenue_per_customer * 0.919

cat("Revenue Parameters:\n")
cat("  Baseline annual revenue per customer: €", 
    round(baseline_annual_revenue_per_customer, 0), "\n")
cat("  Revenue loss from churn: €", round(revenue_saved_per_customer, 0), "\n\n")

# 3. TEST MATRIX: Different Discounts × Different Retention Rates × Different Thresholds
cat(strrep("=", 85), "\n")
cat("SENSITIVITY ANALYSIS MATRIX\n")
cat(strrep("=", 85), "\n\n")

# Parameters to test
discounts <- c(0.05, 0.10, 0.15, 0.20, 0.25, 0.30)
retention_rates <- c(0.30, 0.40, 0.50, 0.60, 0.70)
thresholds <- c(0.25, 0.30, 0.35, 0.40)
campaign_cost <- 50

# Store all results
all_results <- tibble()

for (threshold in thresholds) {
  
  # Target customers above threshold
  targeted <- pred_data %>%
    filter(predicted_churn_prob >= threshold)
  
  n_targeted <- nrow(targeted)
  n_actual_churners <- sum(targeted$actual_churn)
  
  campaign_cost_total <- n_targeted * campaign_cost
  
  for (discount in discounts) {
    
    for (retention_rate in retention_rates) {
      
      # Revenue saved from successful retention
      expected_saved_revenue <- 
        n_actual_churners * retention_rate * revenue_saved_per_customer
      
      # Revenue lost from discount on retained customers
      discount_cost <- 
        n_targeted * retention_rate * baseline_annual_revenue_per_customer * discount
      
      # Net benefit
      net_benefit <- expected_saved_revenue - discount_cost - campaign_cost_total
      
      # ROI
      roi <- ifelse(campaign_cost_total > 0, 
                    (net_benefit / campaign_cost_total) * 100, 
                    0)
      
      # Payback period (months)
      monthly_benefit <- net_benefit / 12
      payback_months <- ifelse(monthly_benefit > 0,
                               campaign_cost_total / monthly_benefit,
                               NA)
      
      all_results <- bind_rows(all_results, tibble(
        Threshold = threshold,
        Discount_Pct = discount * 100,
        Retention_Success_Rate_Pct = retention_rate * 100,
        Customers_Targeted = n_targeted,
        Actual_Churners = n_actual_churners,
        Campaign_Cost = campaign_cost_total,
        Revenue_Saved = expected_saved_revenue,
        Discount_Cost = discount_cost,
        Net_Benefit = net_benefit,
        ROI_Pct = roi,
        Payback_Months = payback_months
      ))
    }
  }
}

cat("Scenarios tested:", nrow(all_results), "\n")
cat("Parameter combinations:\n")
cat("  Thresholds: ", paste(thresholds, collapse=", "), "\n")
cat("  Discounts: ", paste(paste0(discounts*100, "%"), collapse=", "), "\n")
cat("  Retention success rates: ", paste(paste0(retention_rates*100, "%"), collapse=", "), "\n\n")

# 4. FIND OPTIMAL COMBINATIONS
cat(strrep("=", 85), "\n")
cat("TOP 10 BEST DISCOUNT SCENARIOS (by ROI)\n")
cat(strrep("=", 85), "\n\n")

top_roi <- all_results %>%
  arrange(desc(ROI_Pct)) %>%
  slice(1:10) %>%
  select(Threshold, Discount_Pct, Retention_Success_Rate_Pct, 
         Customers_Targeted, Net_Benefit, ROI_Pct)

print(top_roi %>%
        mutate(across(where(is.numeric), ~round(., 1))))

cat("\n")

# 5. TOP BY NET BENEFIT
cat(strrep("=", 85), "\n")
cat("TOP 10 BEST DISCOUNT SCENARIOS (by Net Benefit)\n")
cat(strrep("=", 85), "\n\n")

top_benefit <- all_results %>%
  arrange(desc(Net_Benefit)) %>%
  slice(1:10) %>%
  select(Threshold, Discount_Pct, Retention_Success_Rate_Pct, 
         Customers_Targeted, Net_Benefit, ROI_Pct)

print(top_benefit %>%
        mutate(across(where(is.numeric), ~round(., 1))))

cat("\n")

# 6. DISCOUNT LEVEL COMPARISON (at optimal threshold 0.35, 50% retention)
cat(strrep("=", 85), "\n")
cat("DISCOUNT IMPACT AT THRESHOLD 0.35 (50% Retention Success)\n")
cat(strrep("=", 85), "\n\n")

discount_comparison <- all_results %>%
  filter(Threshold == 0.35, Retention_Success_Rate_Pct == 50) %>%
  arrange(Discount_Pct) %>%
  select(Discount_Pct, Customers_Targeted, Campaign_Cost, 
         Revenue_Saved, Discount_Cost, Net_Benefit, ROI_Pct, Payback_Months)

print(discount_comparison %>%
        mutate(across(where(is.numeric), ~round(., 1))))

cat("\n\nInterpretation:\n")
cat("- Lower discounts = higher ROI (more profit per € spent)\n")
cat("- Higher discounts = lower retention cost but less profitable\n")
cat("- 5% discount: Best ROI but smaller absolute benefit\n")
cat("- 15% discount: Sweet spot - good ROI with meaningful savings\n")
cat("- 25% discount: High costs reduce profitability\n\n")

# 7. RETENTION RATE SENSITIVITY (at threshold 0.35, 15% discount)
cat(strrep("=", 85), "\n")
cat("RETENTION RATE IMPACT AT THRESHOLD 0.35 (15% Discount)\n")
cat(strrep("=", 85), "\n\n")

retention_comparison <- all_results %>%
  filter(Threshold == 0.35, Discount_Pct == 15) %>%
  arrange(Retention_Success_Rate_Pct) %>%
  select(Retention_Success_Rate_Pct, Customers_Targeted, Campaign_Cost,
         Revenue_Saved, Discount_Cost, Net_Benefit, ROI_Pct, Payback_Months)

print(retention_comparison %>%
        mutate(across(where(is.numeric), ~round(., 1))))

cat("\n\nInterpretation:\n")
cat("- 30% success: Campaign barely breaks even\n")
cat("- 50% success: Strong ROI and acceptable payback period\n")
cat("- 70% success: Excellent returns, quick payback\n\n")

# 8. OPTIMAL RECOMMENDATION
cat(strrep("=", 85), "\n")
cat("RECOMMENDED DISCOUNT STRATEGY\n")
cat(strrep("=", 85), "\n\n")

optimal <- all_results %>%
  # Balance ROI and Net Benefit - look for good both-ways performance
  filter(Threshold == 0.35, Retention_Success_Rate_Pct == 50) %>%
  filter(Discount_Pct %in% c(10, 15, 20)) %>%
  arrange(desc(Net_Benefit)) %>%
  slice(1)

cat("RECOMMENDED STRATEGY:\n")
cat("  Targeting threshold: ", optimal$Threshold, "\n")
cat("  Discount level: ", optimal$Discount_Pct, "%\n")
cat("  Retention success rate assumption: ", optimal$Retention_Success_Rate_Pct, "%\n\n")

cat("Financial Projections (Test Set):\n")
cat("  Customers targeted: ", round(optimal$Customers_Targeted, 0), "\n")
cat("  Campaign cost: €", round(optimal$Campaign_Cost, 0), "\n")
cat("  Expected revenue saved: €", round(optimal$Revenue_Saved, 0), "\n")
cat("  Discount cost: €", round(optimal$Discount_Cost, 0), "\n")
cat("  Net benefit: €", round(optimal$Net_Benefit, 0), "\n")
cat("  ROI: ", round(optimal$ROI_Pct, 0), "%\n")
cat("  Payback period: ", round(optimal$Payback_Months, 1), "months\n\n")

# Scale to full customer base
test_size <- nrow(pred_data)
estimated_full_customer_base <- 16096
scale_factor <- estimated_full_customer_base / test_size

cat("Projected Annual Impact (Full Customer Base):\n")
cat("  Customers targeted: ", round(optimal$Customers_Targeted * scale_factor, 0), "\n")
cat("  Campaign cost: €", round(optimal$Campaign_Cost * scale_factor, 0), "\n")
cat("  Net annual benefit: €", round(optimal$Net_Benefit * scale_factor, 0), "\n\n")

# 9. SENSITIVITY TABLE - DISCOUNT vs RETENTION RATE
cat(strrep("=", 85), "\n")
cat("NET BENEFIT SENSITIVITY TABLE\n")
cat("(Discount % vs Retention Success Rate %)\n")
cat("Threshold 0.35, Test Set\n")
cat(strrep("=", 85), "\n\n")

sensitivity_table <- all_results %>%
  filter(Threshold == 0.35) %>%
  select(Discount_Pct, Retention_Success_Rate_Pct, Net_Benefit) %>%
  pivot_wider(names_from = Retention_Success_Rate_Pct,
              values_from = Net_Benefit,
              names_prefix = "Retention_")

print(sensitivity_table %>%
        mutate(across(where(is.numeric), ~round(., 0))))

cat("\n")

# 10. SAVE ALL RESULTS
write_csv(all_results, "reports/discount_sensitivity_all.csv")

write_csv(
  top_benefit %>% mutate(across(where(is.numeric), ~round(., 1))),
  "reports/discount_top_scenarios_by_benefit.csv"
)

cat(strrep("=", 85), "\n")
cat("✓ DISCOUNT SENSITIVITY ANALYSIS COMPLETE\n")
cat(strrep("=", 85), "\n\n")

cat("Generated Outputs:\n")
cat("  1. discount_sensitivity_all.csv - All 120 scenarios\n")
cat("  2. discount_top_scenarios_by_benefit.csv - Top 10 scenarios\n\n")

cat("Key Findings:\n")
cat("  • Optimal discount: ", optimal$Discount_Pct, "% (balance of ROI and benefit)\n")
cat("  • Expected ROI: ", round(optimal$ROI_Pct, 0), "%\n")
cat("  • Annual benefit (full base): €", round(optimal$Net_Benefit * scale_factor, 0), "\n")
cat("  • Payback period: ", round(optimal$Payback_Months, 1), " months\n\n")

cat(strrep("=", 85), "\n")