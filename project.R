# Load necessary libraries
library(shiny)
library(shinydashboard)
library(shinythemes)
library(ggplot2)
library(forecast)
library(tseries)
library(plotly)
library(DT)
library(dplyr)
library(tidyr)
library(lubridate)

# Define UI
ui <- dashboardPage(
  skin = "blue",
  
  dashboardHeader(title = "Time Series Analytics"),
  
  dashboardSidebar(
    sidebarMenu(
      menuItem("Dashboard", tabName = "dashboard", icon = icon("dashboard")),
      menuItem("Analysis", tabName = "analysis", icon = icon("chart-line")),
      menuItem("Forecast", tabName = "forecast", icon = icon("forward")),
      
      # Controls
      br(),
      div(style = "padding: 0 15px",
          selectInput("dataset", "Select Dataset:",
                      choices = c("Air Passengers" = "AirPassengers",
                                  "CO2 Levels" = "co2",
                                  "Temperature" = "nhtemp"),
                      selected = "AirPassengers"
          ),
          
          numericInput("forecast_period",
                       "Forecast Period:",
                       min = 1, max = 36, value = 12
          ),
          
          selectInput("season_period",
                      "Seasonal Period:",
                      choices = c("Monthly" = 12, "Quarterly" = 4, "None" = 1),
                      selected = 12
          ),
          
          checkboxGroupInput("model_features",
                             "Model Features:",
                             choices = c(
                               "Seasonal Adjustment" = "seasonal",
                               "Box-Cox Transformation" = "boxcox"
                             ),
                             selected = c("seasonal")
          ),
          
          actionButton("run_analysis", "Run Analysis",
                       class = "btn-primary",
                       style = "width: 100%"
          )
      )
    )
  ),
  
  dashboardBody(
    tabItems(
      # Dashboard Tab
      tabItem(tabName = "dashboard",
              fluidRow(
                valueBoxOutput("total_observations"),
                valueBoxOutput("mean_value"),
                valueBoxOutput("forecast_accuracy")
              ),
              
              fluidRow(
                box(
                  title = "Time Series Overview",
                  status = "primary",
                  solidHeader = TRUE,
                  width = 12,
                  plotlyOutput("overview_plot", height = "400px")
                )
              ),
              
              fluidRow(
                box(
                  title = "Seasonal Pattern",
                  status = "info",
                  solidHeader = TRUE,
                  width = 6,
                  plotlyOutput("seasonal_plot")
                ),
                box(
                  title = "Trend Component",
                  status = "info",
                  solidHeader = TRUE,
                  width = 6,
                  plotlyOutput("trend_plot")
                )
              )
      ),
      
      # Analysis Tab
      tabItem(tabName = "analysis",
              fluidRow(
                box(
                  title = "Time Series Decomposition",
                  status = "primary",
                  solidHeader = TRUE,
                  width = 12,
                  plotOutput("decomposed_plot", height = "600px")
                )
              ),
              
              fluidRow(
                box(
                  title = "Statistical Tests",
                  status = "info",
                  width = 12,
                  tableOutput("statistical_tests")
                )
              )
      ),
      
      # Forecast Tab
      tabItem(tabName = "forecast",
              fluidRow(
                box(
                  title = "ARIMA Model Forecast",
                  status = "primary",
                  solidHeader = TRUE,
                  width = 12,
                  plotlyOutput("forecast_plot", height = "400px")
                )
              ),
              
              fluidRow(
                box(
                  title = "Model Summary",
                  status = "info",
                  width = 6,
                  verbatimTextOutput("model_summary")
                ),
                box(
                  title = "Forecast Metrics",
                  status = "info",
                  width = 6,
                  tableOutput("forecast_metrics")
                )
              )
      )
    )
  )
)

# Server Logic
server <- function(input, output, session) {
  
  # Reactive Data
  ts_data <- reactive({
    data <- get(input$dataset)
    # Ensure the data is a time series object
    if (!is.ts(data)) {
      data <- ts(data, frequency = as.numeric(input$season_period))
    }
    return(data)
  })
  
  # Create time sequence for plotting
  time_seq <- reactive({
    seq_along(ts_data())
  })
  
  # Decomposition (with error handling)
  ts_decomposition <- reactive({
    req(ts_data())
    tryCatch({
      if (frequency(ts_data()) > 1) {
        decompose(ts_data(), type = "multiplicative")
      } else {
        NULL
      }
    }, error = function(e) {
      NULL
    })
  })
  
  # Fit Model
  model <- reactive({
    req(input$run_analysis)
    
    seasonal <- "seasonal" %in% input$model_features
    use_boxcox <- "boxcox" %in% input$model_features
    
    tryCatch({
      auto.arima(ts_data(),
                 seasonal = seasonal,
                 lambda = if(use_boxcox) "auto" else NULL
      )
    }, error = function(e) {
      showNotification("Error fitting model. Try different parameters.", type = "error")
      NULL
    })
  })
  
  # Generate Forecast
  forecast_data <- reactive({
    req(model())
    forecast(model(), h = input$forecast_period)
  })
  
  # Dashboard Outputs
  output$total_observations <- renderValueBox({
    valueBox(
      length(ts_data()),
      "Total Observations",
      icon = icon("chart-line"),
      color = "blue"
    )
  })
  
  output$mean_value <- renderValueBox({
    valueBox(
      round(mean(ts_data()), 2),
      "Mean Value",
      icon = icon("calculator"),
      color = "purple"
    )
  })
  
  output$forecast_accuracy <- renderValueBox({
    req(model())
    accuracy <- accuracy(model())[1, "MAPE"]
    valueBox(
      sprintf("%.2f%%", accuracy),
      "Model MAPE",
      icon = icon("bullseye"),
      color = "green"
    )
  })
  
  # Overview Plot
  output$overview_plot <- renderPlotly({
    df <- data.frame(
      Time = time_seq(),
      Value = as.numeric(ts_data())
    )
    
    plot_ly(data = df, x = ~Time, y = ~Value, type = 'scatter', mode = 'lines',
            line = list(color = 'blue')) %>%
      layout(
        title = "Time Series Overview",
        xaxis = list(title = "Time"),
        yaxis = list(title = "Value")
      )
  })
  
  # Seasonal Plot
  output$seasonal_plot <- renderPlotly({
    req(ts_decomposition())
    
    df <- data.frame(
      Time = 1:frequency(ts_data()),
      Seasonal = ts_decomposition()$seasonal[1:frequency(ts_data())]
    )
    
    plot_ly(data = df, x = ~Time, y = ~Seasonal, type = 'scatter', mode = 'lines',
            line = list(color = 'red')) %>%
      layout(
        title = "Seasonal Pattern",
        xaxis = list(title = "Period"),
        yaxis = list(title = "Seasonal Effect")
      )
  })
  
  # Trend Plot
  output$trend_plot <- renderPlotly({
    req(ts_decomposition())
    
    df <- data.frame(
      Time = time_seq(),
      Trend = as.numeric(ts_decomposition()$trend)
    )
    
    plot_ly(data = df, x = ~Time, y = ~Trend, type = 'scatter', mode = 'lines',
            line = list(color = 'green')) %>%
      layout(
        title = "Trend Component",
        xaxis = list(title = "Time"),
        yaxis = list(title = "Trend")
      )
  })
  
  # Decomposition Plot
  output$decomposed_plot <- renderPlot({
    req(ts_decomposition())
    plot(ts_decomposition())
  })
  
  # Statistical Tests
  output$statistical_tests <- renderTable({
    tryCatch({
      adf_test <- adf.test(ts_data())
      kpss_test <- kpss.test(ts_data())
      
      data.frame(
        Test = c("ADF Test", "KPSS Test"),
        Statistic = round(c(adf_test$statistic, kpss_test$statistic), 4),
        "P-Value" = round(c(adf_test$p.value, kpss_test$p.value), 4)
      )
    }, error = function(e) {
      data.frame(
        Test = "Error",
        Statistic = NA,
        "P-Value" = NA
      )
    })
  })
  
  # Forecast Plot
  output$forecast_plot <- renderPlotly({
    req(forecast_data())
    
    # Combine actual and forecast data
    df_actual <- data.frame(
      Time = time_seq(),
      Value = as.numeric(ts_data()),
      Type = "Actual"
    )
    
    df_forecast <- data.frame(
      Time = max(time_seq()) + 1:length(forecast_data()$mean),
      Value = as.numeric(forecast_data()$mean),
      Type = "Forecast"
    )
    
    # Create plot
    plot_ly() %>%
      add_trace(data = df_actual, x = ~Time, y = ~Value, 
                type = 'scatter', mode = 'lines', name = 'Actual',
                line = list(color = 'blue')) %>%
      add_trace(data = df_forecast, x = ~Time, y = ~Value,
                type = 'scatter', mode = 'lines', name = 'Forecast',
                line = list(color = 'red')) %>%
      layout(
        title = "Forecast",
        xaxis = list(title = "Time"),
        yaxis = list(title = "Value"),
        showlegend = TRUE
      )
  })
  
  # Model Summary
  output$model_summary <- renderPrint({
    req(model())
    summary(model())
  })
  
  # Forecast Metrics
  output$forecast_metrics <- renderTable({
    req(model())
    accuracy(model())
  })
  
  # Show loading message during analysis
  observeEvent(input$run_analysis, {
    showNotification("Running analysis...", type = "message", duration = 3)
  })
}

# Run the application
shinyApp(ui = ui, server = server)