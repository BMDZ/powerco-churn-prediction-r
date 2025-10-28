# 02_Feature_Engineering.R - PowerCo Customer Churn Prediction
# Feature Engineering and Selection
# ==============================================

library(tidyverse)
library(lubridate)
library(fastDummies)

# 1. Load raw data --------------------------------------------------------------
train <- read_csv("data/raw/ml_case_training_data.csv")
hist  <- read_csv("data/raw/ml_case_training_hist_data.csv")
out   <- read_csv("data/raw/ml_case_training_output.csv")

df <- train %>% left_join(out, by="id") %>% left_join(hist, by="id")

# 2. Convert Dates --------------------------------------------------------------
date_cols <- c("date_activ","date_end","date_first_activ","date_modif_prod","date_renewal","price_date")
df[date_cols] <- map(df[date_cols], ~as_date(.x, format="%Y-%m-%d"))

ref <- ymd("2016-01-31")

# 3. Temporal Features ---------------------------------------------------------
df <- df %>% mutate(
  days_to_renew = as.numeric(date_renewal - ref),
  tenure_days   = as.numeric(ref - date_activ),
  contract_len  = as.numeric(date_end - date_activ),
  days_mod      = as.numeric(ref - date_modif_prod)
)

# 4. Consumption Features ------------------------------------------------------
df <- df %>% mutate(
  avg_mon_cons = cons_12m / 12,
  cons_trend   = cons_last_month / (avg_mon_cons + 1),
  cons_pct     = (cons_last_month - avg_mon_cons) / (avg_mon_cons +1) * 100,
  total_cons   = cons_12m + cons_gas_12m
)

# 5. Economic Features ---------------------------------------------------------
df <- df %>% mutate(
  margin_pc = net_margin / (cons_12m + 1),
  est_rev   = cons_12m * price_p1_fix,
  disc_rate = forecast_discount_energy / (est_rev + 1)
)

# 6. Categorical Encoding ------------------------------------------------------
df <- df %>% mutate(
  activity_new = fct_lump(activity_new, n = 10),
  channel_sales = fct_lump(channel_sales, n = 10)
) %>% 
  fastDummies::dummy_cols(select_columns = c("activity_new", "channel_sales", "origin_up"), remove_first_dummy = TRUE)

# 7. Impute Missing -----------------------------------------------------------
num_cols <- df %>% select(where(is.numeric)) %>% names()
df[num_cols] <- df[num_cols] %>% map_dfc(~replace_na(.x, median(.x, na.rm = TRUE)))

# 8. Feature Selection (numeric-only) -----------------------------------------
num_cols <- df %>% select(-id, -churn) %>% select(where(is.numeric)) %>% names()
corr_mat <- df %>% select(all_of(num_cols), churn) %>% cor(use = "complete.obs")
ord <- sort(abs(corr_mat[,"churn"]), decreasing = TRUE)
selected <- names(ord)[2:26]   # Top 25 features excluding churn itself

# 9. Save selected features ----------------------------------------------------
dir.create("data/processed", recursive = TRUE, showWarnings=FALSE)
df %>%
  select(id, churn, all_of(selected)) %>%
  write_csv("data/processed/features_selected.csv")

cat("Feature engineering complete! Selected features saved:\n", paste(selected, collapse = ", "), "\n")
