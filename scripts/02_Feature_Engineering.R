# 02_Feature_Engineering_OUTLIER_REMOVAL.R - PowerCo Churn
# WITH OUTLIER HANDLING (the missing piece!)
# ===============================================================

library(tidyverse)
library(lubridate)
library(fastDummies)

cat("\n")
cat(strrep("=", 85), "\n")
cat("FEATURE ENGINEERING WITH OUTLIER REMOVAL\n")
cat(strrep("=", 85), "\n\n")

# 1. Load and aggregate data
train <- read_csv("ml_case_training_data.csv")
hist  <- read_csv("ml_case_training_hist_data.csv")
out   <- read_csv("ml_case_training_output.csv")

hist_agg <- hist %>%
  group_by(id) %>%
  summarise(
    price_p1_var_mean = mean(price_p1_var, na.rm = TRUE),
    price_p2_var_mean = mean(price_p2_var, na.rm = TRUE),
    price_p3_var_mean = mean(price_p3_var, na.rm = TRUE),
    price_p1_fix_mean = mean(price_p1_fix, na.rm = TRUE),
    price_p2_fix_mean = mean(price_p2_fix, na.rm = TRUE),
    price_p3_fix_mean = mean(price_p3_fix, na.rm = TRUE),
    price_months = n(),
    .groups = "drop"
  )

df <- train %>% 
  left_join(out, by="id") %>% 
  left_join(hist_agg, by="id")

cat("Initial data: ", nrow(df), "rows\n\n")

# ===== CRITICAL: OUTLIER REMOVAL USING IQR METHOD =====
cat("REMOVING OUTLIERS (IQR method: 1.5 × IQR)\n")
cat(strrep("-", 85), "\n\n")

# Function to remove outliers using IQR method
remove_outliers_iqr <- function(x) {
  Q1 <- quantile(x, 0.25, na.rm = TRUE)
  Q3 <- quantile(x, 0.75, na.rm = TRUE)
  IQR_val <- Q3 - Q1
  lower_bound <- Q1 - 1.5 * IQR_val
  upper_bound <- Q3 + 1.5 * IQR_val
  
  # Replace outliers with upper/lower bounds (cap, don't remove)
  x_capped <- pmin(pmax(x, lower_bound), upper_bound)
  
  # Count replaced
  n_outliers <- sum((x < lower_bound | x > upper_bound), na.rm = TRUE)
  
  return(list(x = x_capped, outliers = n_outliers))
}

# Define columns to handle outliers (consumption and margin features)
outlier_cols <- c(
  "cons_12m", "cons_gas_12m", "cons_last_month",
  "forecast_cons_12m", "forecast_cons_year", "forecast_cons",
  "net_margin", "margin_gross_pow_ele", "margin_net_pow_ele",
  "forecast_discount_energy", "pow_max", "imp_cons"
)

# Apply outlier removal
for (col in outlier_cols) {
  if (col %in% names(df)) {
    result <- remove_outliers_iqr(df[[col]])
    df[[col]] <- result$x
    if (result$outliers > 0) {
      cat("  Capped", result$outliers, "outliers in", col, "\n")
    }
  }
}

cat("\n")

# 2. Create reference date
ref <- ymd("2016-01-31")

# 3. ENHANCED FEATURE ENGINEERING (now with clean data)
df <- df %>% mutate(
  # ===== TEMPORAL FEATURES =====
  days_to_renew = as.numeric(date_renewal - ref),
  tenure_days = as.numeric(ref - date_activ),
  contract_len = as.numeric(date_end - date_activ),
  days_mod = as.numeric(ref - date_modif_prod),
  
  # ===== CONSUMPTION FEATURES (NOW CLEAN) =====
  avg_mon_cons = cons_12m / 12,
  cons_trend = cons_last_month / (avg_mon_cons + 1),
  cons_pct = (cons_last_month - avg_mon_cons) / (avg_mon_cons + 1) * 100,
  total_cons = cons_12m + cons_gas_12m,
  
  # ===== ECONOMIC FEATURES (NOW CLEAN) =====
  margin_pc = net_margin / (cons_12m + 1),
  est_rev = cons_12m * price_p1_fix_mean,
  disc_rate = forecast_discount_energy / (est_rev + 1),
  
  # ===== INTERACTION FEATURES (STRONGER NOW WITH CLEAN DATA) =====
  engagement_risk = (cons_last_month / (avg_mon_cons + 1)) * (days_mod / 365),
  stability_score = (net_margin / 300) * (contract_len / 1000),
  revenue_efficiency = est_rev / (net_margin + 100),
  
  tenure_normalized = tenure_days / 365,
  tenure_squared = tenure_normalized ^ 2,
  
  price_volatility = abs(price_p1_var_mean - price_p1_fix_mean),
  consumption_decline = cons_last_month - avg_mon_cons,
  consumption_decline_pct = consumption_decline / (avg_mon_cons + 1),
  
  has_gas_flag = as.numeric(has_gas),
  num_products = 1 + has_gas_flag,
  
  contract_len_short = as.numeric(contract_len < 365),
  low_margin = as.numeric(net_margin < 100),
  high_margin = as.numeric(net_margin > 500),
  
  antig_contract_ratio = num_years_antig / (contract_len / 365 + 1),
  forecast_vs_actual = forecast_cons_12m - avg_mon_cons,
  power_intensity = pow_max / (cons_12m + 1),
  discount_exposure = forecast_discount_energy / (forecast_cons_12m + 1),
  recent_mod_low_cons = days_mod * consumption_decline_pct,
  activity_premium = num_years_antig * tenure_normalized
)

cat("Enhanced features created.\n\n")

# 4. Categorical encoding
df <- df %>%
  mutate(
    activity_new = fct_lump(activity_new, n = 10),
    channel_sales = fct_lump(channel_sales, n = 10)
  ) %>%
  fastDummies::dummy_cols(
    select_columns = c("activity_new", "channel_sales", "origin_up"),
    remove_first_dummy = TRUE
  )

cat("Categorical features encoded.\n\n")

# 5. Impute missing
num_cols <- df %>% select(where(is.numeric)) %>% names()
df[num_cols] <- df[num_cols] %>%
  map_dfc(~replace_na(.x, median(.x, na.rm = TRUE)))

# 6. Handle infinite values
df[num_cols] <- df[num_cols] %>%
  map_dfc(~replace(.x, is.infinite(.x), 0))

cat("Missing values imputed, infinities handled.\n\n")

# 7. Feature selection: TOP 30 by correlation
num_cols_pred <- df %>%
  select(-id, -churn) %>%
  select(where(is.numeric)) %>%
  names()

corr_mat <- df %>%
  select(all_of(num_cols_pred), churn) %>%
  cor(use = "complete.obs")

ord <- sort(abs(corr_mat[, "churn"]), decreasing = TRUE)

cat("TOP 20 FEATURES BY CORRELATION (with outliers removed):\n")
print(ord[2:21])
cat("\n")

selected <- names(ord)[2:min(31, length(ord))]

cat("Selected ", length(selected), "features\n\n")

# 8. Save
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

df_final <- df %>%
  select(id, churn, all_of(selected)) %>%
  mutate(churn = as.integer(churn))

write_csv(df_final, "data/processed/features_selected.csv")

cat(strrep("=", 85), "\n")
cat("✓ Feature engineering WITH OUTLIER REMOVAL COMPLETE\n")
cat("  Dataset: ", nrow(df_final), " rows x ", ncol(df_final), " columns\n")
cat("  Churn distribution:\n")
print(table(df_final$churn))
cat(strrep("=", 85), "\n\n")

