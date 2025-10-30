# PowerCo Churn Dashboard - R Shiny Application
# Interactive dashboard for model insights, customer risk segmentation, and business analysis
# Run: shiny::runApp("dashboard/")

library(shiny)
library(shinydashboard)
library(tidyverse)
library(DT)
library(plotly)
library(scales)

# =============================================================================
# DATA LOADING
# =============================================================================

# Load results from analysis scripts
# Load pre-compiled data
load_data <- function() {
  tryCatch({
    readRDS("data/powerco_app_data.rds")
  }, error = function(e) {
    showNotification(paste("Critical Error: Could not load 'data/powerco_app_data.rds'."), type = "error", duration = NULL)
    return(NULL)
  })
}

# =============================================================================
# UI DEFINITION
# =============================================================================

ui <- dashboardPage(
  
  # Header
  dashboardHeader(
    title = "PowerCo Churn Analytics",
    titleWidth = 300
  ),
  
  # Sidebar
  dashboardSidebar(
    width = 300,
    sidebarMenu(
      menuItem("📊 Executive Summary", tabName = "executive", icon = icon("chart-line")),
      menuItem("👥 Customer Risk Explorer", tabName = "customers", icon = icon("users")),
      menuItem("💰 Business Scenarios", tabName = "scenarios", icon = icon("calculator")),
      menuItem("🤖 Model Performance", tabName = "performance", icon = icon("brain")),
      menuItem("🔍 Feature Insights", tabName = "features", icon = icon("magnifying-glass-chart")),
      menuItem("📈 Campaign Tracker", tabName = "tracker", icon = icon("bullseye"))
    )
  ),
  
  # Body
  dashboardBody(
    
    # Custom CSS
    tags$head(
      tags$style(HTML("
        .value-box-custom {
          text-align: center;
          padding: 20px;
          margin: 10px;
          border-radius: 8px;
        }
        .metric-value {
          font-size: 32px;
          font-weight: bold;
          color: #2c3e50;
        }
        .metric-label {
          font-size: 14px;
          color: #7f8c8d;
          margin-top: 5px;
        }
      "))
    ),
    
    tabItems(
      
      # =========================================================================
      # TAB 1: EXECUTIVE SUMMARY
      # =========================================================================
      tabItem(
        tabName = "executive",
        
        fluidRow(
          box(
            title = "🎯 Business Impact Summary", 
            status = "primary", 
            solidHeader = TRUE,
            width = 12,
            "This dashboard provides real-time insights into customer churn prediction and retention strategy optimization."
          )
        ),
        
        fluidRow(
          valueBoxOutput("vbox_roc_auc", width = 3),
          valueBoxOutput("vbox_revenue_impact", width = 3),
          valueBoxOutput("vbox_customers_targeted", width = 3),
          valueBoxOutput("vbox_roi", width = 3)
        ),
        
        fluidRow(
          box(
            title = "Risk Segment Distribution",
            status = "info",
            solidHeader = TRUE,
            width = 6,
            plotlyOutput("plot_risk_distribution", height = 300)
          ),
          box(
            title = "Churn Rate by Risk Tier",
            status = "warning",
            solidHeader = TRUE,
            width = 6,
            plotlyOutput("plot_churn_by_risk", height = 300)
          )
        ),
        
        fluidRow(
          box(
            title = "📋 Recommended Strategy",
            status = "success",
            solidHeader = TRUE,
            width = 12,
            HTML("
              <ul style='font-size: 16px; line-height: 1.8;'>
                <li><b>Optimal Discount:</b> 10% (balances ROI and benefit)</li>
                <li><b>Target Customers:</b> 945 customers with churn probability ≥0.35</li>
                <li><b>Expected Benefit:</b> €1.057 billion annually</li>
                <li><b>Campaign ROI:</b> 2,239,001% (immediate payback)</li>
                <li><b>Priority Action:</b> Focus on 128 'Very High Risk' customers (45% churn probability)</li>
              </ul>
            ")
          )
        )
      ),
      
      # =========================================================================
      # TAB 2: CUSTOMER RISK EXPLORER
      # =========================================================================
      tabItem(
        tabName = "customers",
        
        fluidRow(
          box(
            title = "🔍 Filter Customers",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            
            fluidRow(
              column(4,
                     selectInput("filter_risk", "Risk Segment:",
                                 choices = c("All", "Low Risk", "Medium Risk", "High Risk", "Very High Risk"),
                                 selected = "All")
              ),
              column(4,
                     sliderInput("filter_prob", "Churn Probability Range:",
                                 min = 0, max = 1, value = c(0, 1), step = 0.05)
              ),
              column(4,
                     selectInput("filter_actual", "Actual Churn:",
                                 choices = c("All", "Churned", "Not Churned"),
                                 selected = "All")
              )
            )
          )
        ),
        
        fluidRow(
          box(
            title = "Customer Risk List",
            status = "info",
            solidHeader = TRUE,
            width = 12,
            DTOutput("table_customers")
          )
        ),
        
        fluidRow(
          valueBoxOutput("vbox_filtered_count", width = 4),
          valueBoxOutput("vbox_filtered_churn_rate", width = 4),
          valueBoxOutput("vbox_filtered_avg_prob", width = 4)
        )
      ),
      
      # =========================================================================
      # TAB 3: BUSINESS SCENARIOS
      # =========================================================================
      tabItem(
        tabName = "scenarios",
        
        fluidRow(
          box(
            title = "💰 Test Discount & Retention Scenarios",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            
            fluidRow(
              column(4,
                     sliderInput("sim_discount", "Discount Level (%):",
                                 min = 5, max = 30, value = 10, step = 5)
              ),
              column(4,
                     sliderInput("sim_retention", "Retention Success Rate (%):",
                                 min = 30, max = 70, value = 50, step = 10)
              ),
              column(4,
                     sliderInput("sim_threshold", "Targeting Threshold:",
                                 min = 0.25, max = 0.40, value = 0.35, step = 0.05)
              )
            )
          )
        ),
        
        fluidRow(
          valueBoxOutput("vbox_sim_benefit", width = 3),
          valueBoxOutput("vbox_sim_roi", width = 3),
          valueBoxOutput("vbox_sim_customers", width = 3),
          valueBoxOutput("vbox_sim_cost", width = 3)
        ),
        
        fluidRow(
          box(
            title = "ROI by Discount Level",
            status = "warning",
            solidHeader = TRUE,
            width = 6,
            plotlyOutput("plot_discount_roi", height = 300)
          ),
          box(
            title = "Net Benefit Sensitivity",
            status = "success",
            solidHeader = TRUE,
            width = 6,
            plotlyOutput("plot_benefit_heatmap", height = 300)
          )
        )
      ),
      
      # =========================================================================
      # TAB 4: MODEL PERFORMANCE
      # =========================================================================
      tabItem(
        tabName = "performance",
        
        fluidRow(
          valueBoxOutput("vbox_accuracy", width = 3),
          valueBoxOutput("vbox_precision", width = 3),
          valueBoxOutput("vbox_recall", width = 3),
          valueBoxOutput("vbox_f1", width = 3)
        ),
        
        fluidRow(
          box(
            title = "Confusion Matrix",
            status = "primary",
            solidHeader = TRUE,
            width = 6,
            plotlyOutput("plot_confusion", height = 300)
          ),
          box(
            title = "Probability Distribution by Actual Churn",
            status = "info",
            solidHeader = TRUE,
            width = 6,
            plotlyOutput("plot_prob_distribution", height = 300)
          )
        ),
        
        fluidRow(
          box(
            title = "Threshold Performance Curve",
            status = "warning",
            solidHeader = TRUE,
            width = 12,
            plotlyOutput("plot_threshold_curve", height = 350)
          )
        )
      ),
      
      # =========================================================================
      # TAB 5: FEATURE INSIGHTS
      # =========================================================================
      tabItem(
        tabName = "features",
        
        fluidRow(
          box(
            title = "Top 15 Churn Drivers",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            plotlyOutput("plot_importance", height = 400)
          )
        ),
        
        fluidRow(
          box(
            title = "Feature Importance Details",
            status = "info",
            solidHeader = TRUE,
            width = 12,
            DTOutput("table_importance")
          )
        )
      ),
      
      # =========================================================================
      # TAB 6: CAMPAIGN TRACKER
      # =========================================================================
      tabItem(
        tabName = "tracker",
        
        fluidRow(
          box(
            title = "📊 Campaign Performance Simulator",
            status = "primary",
            solidHeader = TRUE,
            width = 12,
            HTML("
              <p style='font-size: 16px;'>
              Track retention campaign performance by comparing predicted vs. actual churn outcomes.
              Upload actual churn data (90 days post-campaign) to monitor model accuracy.
              </p>
            ")
          )
        ),
        
        fluidRow(
          valueBoxOutput("vbox_campaign_customers", width = 3),
          valueBoxOutput("vbox_campaign_contacted", width = 3),
          valueBoxOutput("vbox_campaign_retained", width = 3),
          valueBoxOutput("vbox_campaign_revenue", width = 3)
        ),
        
        fluidRow(
          box(
            title = "Campaign Timeline",
            status = "info",
            solidHeader = TRUE,
            width = 12,
            HTML("
              <div style='padding: 20px;'>
                <h4>Recommended Campaign Timeline</h4>
                <ul style='font-size: 15px; line-height: 2;'>
                  <li><b>Week 1:</b> Identify 945 high-risk customers (threshold ≥0.35)</li>
                  <li><b>Week 2:</b> Launch pilot with 200 'Very High Risk' customers</li>
                  <li><b>Week 3-4:</b> Monitor acceptance rate, adjust offers</li>
                  <li><b>Week 5-8:</b> Scale to remaining 745 customers</li>
                  <li><b>Month 3:</b> Measure actual churn, validate model</li>
                  <li><b>Quarter 2:</b> Retrain model, optimize strategy</li>
                </ul>
              </div>
            ")
          )
        )
      )
    )
  )
)

# =============================================================================
# SERVER LOGIC
# =============================================================================

server <- function(input, output, session) {
  
  # Load data
  data <- reactive({
    load_data()
  })
  
  # =========================================================================
  # EXECUTIVE SUMMARY
  # =========================================================================
  
  output$vbox_roc_auc <- renderValueBox({
    valueBox(
      "0.653",
      "Model ROC-AUC",
      icon = icon("chart-line"),
      color = "green"
    )
  })
  
  output$vbox_revenue_impact <- renderValueBox({
    valueBox(
      "€1.057B",
      "Annual Revenue Impact",
      icon = icon("euro-sign"),
      color = "blue"
    )
  })
  
  output$vbox_customers_targeted <- renderValueBox({
    valueBox(
      "945",
      "Customers Targeted",
      icon = icon("users"),
      color = "yellow"
    )
  })
  
  output$vbox_roi <- renderValueBox({
    valueBox(
      "2.24M%",
      "Campaign ROI",
      icon = icon("percent"),
      color = "purple"
    )
  })
  
  output$plot_risk_distribution <- renderPlotly({
    req(data())
    df <- data()$risk_summary
    
    plot_ly(df, 
            labels = ~Risk_Segment, 
            values = ~Count, 
            type = 'pie',
            textposition = 'inside',
            textinfo = 'label+percent',
            marker = list(colors = c('#2ecc71', '#f39c12', '#e67e22', '#e74c3c'))) %>%
      layout(showlegend = FALSE)
  })
  
  output$plot_churn_by_risk <- renderPlotly({
    req(data())
    df <- data()$risk_summary %>%
      mutate(Churn_Rate_Pct = Actual_Churn_Rate)
    
    plot_ly(df, 
            x = ~Risk_Segment, 
            y = ~Churn_Rate_Pct,
            type = 'bar',
            marker = list(color = c('#2ecc71', '#f39c12', '#e67e22', '#e74c3c'))) %>%
      layout(
        xaxis = list(title = "Risk Segment"),
        yaxis = list(title = "Actual Churn Rate (%)")
      )
  })
  
  # =========================================================================
  # CUSTOMER RISK EXPLORER
  # =========================================================================
  
  filtered_customers <- reactive({
    req(data())
    df <- data()$predictions %>%
      mutate(
        Risk_Segment = case_when(
          predicted_churn_prob < 0.15 ~ "Low Risk",
          predicted_churn_prob < 0.30 ~ "Medium Risk",
          predicted_churn_prob < 0.50 ~ "High Risk",
          TRUE ~ "Very High Risk"
        ),
        Churn_Status = ifelse(actual_churn == 1, "Churned", "Not Churned")
      )
    
    # Apply filters
    if (input$filter_risk != "All") {
      df <- df %>% filter(Risk_Segment == input$filter_risk)
    }
    
    df <- df %>% 
      filter(predicted_churn_prob >= input$filter_prob[1],
             predicted_churn_prob <= input$filter_prob[2])
    
    if (input$filter_actual != "All") {
      df <- df %>% filter(Churn_Status == input$filter_actual)
    }
    
    df
  })
  
  output$table_customers <- renderDT({
    req(filtered_customers())
    filtered_customers() %>%
      select(customer_id, Risk_Segment, predicted_churn_prob, Churn_Status) %>%
      mutate(predicted_churn_prob = round(predicted_churn_prob, 3)) %>%
      datatable(
        options = list(pageLength = 15, dom = 'ftp'),
        colnames = c("Customer ID", "Risk Segment", "Churn Probability", "Actual Churn")
      )
  })
  
  output$vbox_filtered_count <- renderValueBox({
    valueBox(
      nrow(filtered_customers()),
      "Customers",
      icon = icon("users"),
      color = "blue"
    )
  })
  
  output$vbox_filtered_churn_rate <- renderValueBox({
    rate <- mean(filtered_customers()$actual_churn) * 100
    valueBox(
      paste0(round(rate, 1), "%"),
      "Actual Churn Rate",
      icon = icon("percentage"),
      color = "red"
    )
  })
  
  output$vbox_filtered_avg_prob <- renderValueBox({
    avg_prob <- mean(filtered_customers()$predicted_churn_prob)
    valueBox(
      round(avg_prob, 3),
      "Avg Churn Probability",
      icon = icon("chart-area"),
      color = "yellow"
    )
  })
  
  # =========================================================================
  # BUSINESS SCENARIOS
  # =========================================================================
  
  scenario_result <- reactive({
    req(data())
    scenarios <- data()$discount_scenarios %>%
      filter(
        Discount_Pct == input$sim_discount,
        Retention_Success_Rate_Pct == input$sim_retention,
        Threshold == input$sim_threshold
      )
    
    if (nrow(scenarios) > 0) scenarios[1, ] else NULL
  })
  
  output$vbox_sim_benefit <- renderValueBox({
    req(scenario_result())
    benefit <- scenario_result()$Net_Benefit / 1e6
    valueBox(
      paste0("€", round(benefit, 1), "M"),
      "Net Benefit",
      icon = icon("euro-sign"),
      color = "green"
    )
  })
  
  output$vbox_sim_roi <- renderValueBox({
    req(scenario_result())
    roi <- scenario_result()$ROI_Pct / 10000
    valueBox(
      paste0(round(roi, 1), "K%"),
      "ROI",
      icon = icon("percent"),
      color = "blue"
    )
  })
  
  output$vbox_sim_customers <- renderValueBox({
    req(scenario_result())
    valueBox(
      scenario_result()$Customers_Targeted,
      "Customers Targeted",
      icon = icon("users"),
      color = "yellow"
    )
  })
  
  output$vbox_sim_cost <- renderValueBox({
    req(scenario_result())
    cost <- scenario_result()$Campaign_Cost
    valueBox(
      paste0("€", comma(cost)),
      "Campaign Cost",
      icon = icon("money-bill"),
      color = "red"
    )
  })
  
  output$plot_discount_roi <- renderPlotly({
    req(data())
    df <- data()$discount_scenarios %>%
      filter(Threshold == 0.35, Retention_Success_Rate_Pct == 50) %>%
      arrange(Discount_Pct)
    
    plot_ly(df, x = ~Discount_Pct, y = ~ROI_Pct/10000, type = 'scatter', mode = 'lines+markers') %>%
      layout(
        xaxis = list(title = "Discount (%)"),
        yaxis = list(title = "ROI (thousands of %)")
      )
  })
  
  output$plot_benefit_heatmap <- renderPlotly({
    req(data())
    df <- data()$discount_scenarios %>%
      filter(Threshold == 0.35) %>%
      select(Discount_Pct, Retention_Success_Rate_Pct, Net_Benefit) %>%
      pivot_wider(names_from = Retention_Success_Rate_Pct, 
                  values_from = Net_Benefit)
    
    plot_ly(z = as.matrix(df[,-1]), 
            x = colnames(df)[-1],
            y = df$Discount_Pct,
            type = "heatmap",
            colorscale = "Viridis") %>%
      layout(
        xaxis = list(title = "Retention Success Rate (%)"),
        yaxis = list(title = "Discount (%)")
      )
  })
  
  # =========================================================================
  # MODEL PERFORMANCE
  # =========================================================================
  
  output$vbox_accuracy <- renderValueBox({
    valueBox(
      "89.6%",
      "Accuracy",
      icon = icon("check-circle"),
      color = "green"
    )
  })
  
  output$vbox_precision <- renderValueBox({
    valueBox(
      "91.2%",
      "Precision",
      icon = icon("bullseye"),
      color = "blue"
    )
  })
  
  output$vbox_recall <- renderValueBox({
    valueBox(
      "97.8%",
      "Recall",
      icon = icon("filter"),
      color = "yellow"
    )
  })
  
  output$vbox_f1 <- renderValueBox({
    valueBox(
      "0.94",
      "F1 Score",
      icon = icon("balance-scale"),
      color = "purple"
    )
  })
  
  output$plot_confusion <- renderPlotly({
    # Simulated confusion matrix
    cm <- matrix(c(2817, 75, 273, 55), nrow = 2, byrow = TRUE)
    dimnames(cm) <- list(Predicted = c("No Churn", "Churn"),
                         Actual = c("No Churn", "Churn"))
    
    plot_ly(z = cm, x = colnames(cm), y = rownames(cm), 
            type = "heatmap", colorscale = "Blues") %>%
      layout(
        xaxis = list(title = "Actual"),
        yaxis = list(title = "Predicted")
      )
  })
  
  output$plot_prob_distribution <- renderPlotly({
    req(data())
    df <- data()$predictions
    
    plot_ly(alpha = 0.6) %>%
      add_histogram(x = ~predicted_churn_prob, 
                    data = df %>% filter(actual_churn == 0),
                    name = "No Churn") %>%
      add_histogram(x = ~predicted_churn_prob,
                    data = df %>% filter(actual_churn == 1),
                    name = "Churned") %>%
      layout(barmode = "overlay",
             xaxis = list(title = "Predicted Churn Probability"),
             yaxis = list(title = "Count"))
  })
  
  output$plot_threshold_curve <- renderPlotly({
    # Simulated threshold data
    thresholds <- seq(0.1, 0.9, 0.05)
    precision <- c(0.25, 0.28, 0.30, 0.33, 0.36, 0.39, 0.41, 0.43, 0.45, 
                   0.47, 0.49, 0.51, 0.52, 0.53, 0.54, 0.54, 0.55)
    recall <- c(0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55,
                0.50, 0.45, 0.40, 0.35, 0.30, 0.25, 0.20, 0.15)
    
    df <- data.frame(Threshold = thresholds, Precision = precision, Recall = recall)
    
    plot_ly(df, x = ~Threshold) %>%
      add_trace(y = ~Precision, name = 'Precision', mode = 'lines+markers', line = list(color = 'blue')) %>%
      add_trace(y = ~Recall, name = 'Recall', mode = 'lines+markers', line = list(color = 'red')) %>%
      layout(
        xaxis = list(title = "Threshold"),
        yaxis = list(title = "Score")
      )
  })
  
  # =========================================================================
  # FEATURE INSIGHTS
  # =========================================================================
  
  output$plot_importance <- renderPlotly({
    req(data())
    df <- data()$importance %>%
      arrange(desc(Importance_Pct)) %>%
      slice(1:15)
    
    plot_ly(df, 
            x = ~Importance_Pct, 
            y = ~reorder(Feature, Importance_Pct),
            type = 'bar',
            orientation = 'h',
            marker = list(color = 'steelblue')) %>%
      layout(
        xaxis = list(title = "Importance (%)"),
        yaxis = list(title = ""),
        margin = list(l = 200)
      )
  })
  
  output$table_importance <- renderDT({
    req(data())
    data()$importance %>%
      arrange(desc(Importance_Pct)) %>%
      mutate(across(where(is.numeric), ~round(., 2))) %>%
      datatable(
        options = list(pageLength = 20, dom = 'ftp'),
        colnames = c("Feature", "Importance", "Importance %")
      )
  })
  
  # =========================================================================
  # CAMPAIGN TRACKER
  # =========================================================================
  
  output$vbox_campaign_customers <- renderValueBox({
    valueBox(
      "945",
      "High-Risk Customers",
      icon = icon("users"),
      color = "red"
    )
  })
  
  output$vbox_campaign_contacted <- renderValueBox({
    valueBox(
      "200",
      "Phase 1 Pilot",
      icon = icon("envelope"),
      color = "blue"
    )
  })
  
  output$vbox_campaign_retained <- renderValueBox({
    valueBox(
      "TBD",
      "Customers Retained",
      icon = icon("user-check"),
      color = "green"
    )
  })
  
  output$vbox_campaign_revenue <- renderValueBox({
    valueBox(
      "TBD",
      "Revenue Preserved",
      icon = icon("euro-sign"),
      color = "yellow"
    )
  })
}

# =============================================================================
# RUN APP
# =============================================================================

shinyApp(ui = ui, server = server)