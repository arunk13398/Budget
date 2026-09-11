package com.budget.planning

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import android.graphics.BitmapFactory
import java.io.File
import java.text.NumberFormat
import java.util.Locale

class NagavalliWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)
        Log.d("NagavalliWidget", "Updating card widget. Data: ${widgetData.all}")

        val numberFormat = NumberFormat.getInstance(Locale("en", "IN"))

        for (appWidgetId in appWidgetIds) {
            try {
                val views = RemoteViews(context.packageName, R.layout.home_widget)
                
                val currentValueStr = widgetData.getString("current_value", "0") ?: "0"
                val maxValueStr = widgetData.getString("max_value", "0") ?: "0"
                val remainingBudgetStr = widgetData.getString("remaining_budget", "0") ?: "0"
                val progress = widgetData.getInt("progress", 0)
                val monthName = widgetData.getString("month_name", "---") ?: "---"
                val cardName = widgetData.getString("card_name", "Budget") ?: "Budget"
                val isWarning = widgetData.getBoolean("is_warning", false)
                
                val valDouble = currentValueStr.toDoubleOrNull() ?: 0.0
                val limitDouble = maxValueStr.toDoubleOrNull() ?: 0.0
                val remainingDouble = remainingBudgetStr.toDoubleOrNull() ?: (limitDouble - valDouble)

                // Format numbers with commas (e.g. ₹9,00,500)
                val formattedSpent = "₹" + formatCurrency(valDouble, numberFormat)
                val formattedLimit = "₹" + formatCurrency(limitDouble, numberFormat)
                val formattedRemaining = if (remainingDouble < 0) {
                    "-₹" + formatCurrency(-remainingDouble, numberFormat)
                } else {
                    "₹" + formatCurrency(remainingDouble, numberFormat)
                }

                views.setTextViewText(R.id.tv_card_name, cardName)
                views.setTextViewText(R.id.tv_current_value, formattedSpent)
                views.setTextViewText(R.id.tv_max_value, formattedLimit)
                views.setTextViewText(R.id.tv_remaining_budget, formattedRemaining)
                views.setTextViewText(R.id.tv_month_name, monthName.uppercase())

                if (isWarning || remainingDouble < 0) {
                    views.setTextColor(R.id.tv_card_name, android.graphics.Color.parseColor("#E53935")) // Red-600
                    views.setTextColor(R.id.tv_remaining_budget, android.graphics.Color.parseColor("#E53935"))
                    views.setTextColor(R.id.tv_current_value, android.graphics.Color.parseColor("#E53935"))
                } else {
                    views.setTextColor(R.id.tv_card_name, android.graphics.Color.parseColor("#9E9E9E"))
                    views.setTextColor(R.id.tv_remaining_budget, android.graphics.Color.BLACK)
                    views.setTextColor(R.id.tv_current_value, android.graphics.Color.BLACK)
                }
                
                views.setViewVisibility(R.id.progress_bar_blue, android.view.View.GONE)
                views.setViewVisibility(R.id.progress_bar_green, android.view.View.GONE)
                views.setViewVisibility(R.id.progress_bar_orange, android.view.View.GONE)
                views.setViewVisibility(R.id.progress_bar_red, android.view.View.GONE)

                val activeProgressBar = when {
                    valDouble <= (limitDouble * 0.4) -> R.id.progress_bar_blue
                    valDouble <= (limitDouble * 0.7) -> R.id.progress_bar_green
                    valDouble <= (limitDouble * 0.9) -> R.id.progress_bar_orange
                    else -> R.id.progress_bar_red
                }
                
                views.setViewVisibility(activeProgressBar, android.view.View.VISIBLE)
                views.setProgressBar(activeProgressBar, 100, progress.coerceIn(0, 100), false)
                
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, android.net.Uri.parse("homeWidget://open"))
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
                
                val syncIntent = HomeWidgetBackgroundIntent.getBroadcast(context, 
                    android.net.Uri.parse("homeWidget://sync"))
                views.setOnClickPendingIntent(R.id.btn_sync, syncIntent)
                
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e("NagavalliWidget", "Error updating card widget", e)
            }
        }
    }

    private fun formatCurrency(amount: Double, formatter: NumberFormat): String {
        return try {
            formatter.format(amount.toLong())
        } catch (e: Exception) {
            amount.toInt().toString()
        }
    }
}

class NagavalliPieWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val widgetData = HomeWidgetPlugin.getData(context)
        Log.d("NagavalliWidget", "Updating pie widget")
        for (appWidgetId in appWidgetIds) {
            try {
                val views = RemoteViews(context.packageName, R.layout.home_widget)
                val chartPath = widgetData.getString("pie_chart_path", null)
                
                if (chartPath != null) {
                    val file = File(chartPath)
                    if (file.exists()) {
                        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                        views.setImageViewBitmap(R.id.iv_pie_chart, bitmap)
                    }
                }
                
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, android.net.Uri.parse("homeWidget://open"))
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
                
                val syncIntent = HomeWidgetBackgroundIntent.getBroadcast(context, android.net.Uri.parse("homeWidget://sync"))
                views.setOnClickPendingIntent(R.id.btn_sync, syncIntent)
                
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e("NagavalliWidget", "Error updating pie widget", e)
            }
        }
    }
}

class NagavalliLineWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val widgetData = HomeWidgetPlugin.getData(context)
        Log.d("NagavalliWidget", "Updating line widget")
        for (appWidgetId in appWidgetIds) {
            try {
                val views = RemoteViews(context.packageName, R.layout.home_widget)
                val chartPath = widgetData.getString("line_chart_path", null)
                
                if (chartPath != null) {
                    val file = File(chartPath)
                    if (file.exists()) {
                        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                        views.setImageViewBitmap(R.id.iv_line_chart, bitmap)
                    }
                }
                
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, android.net.Uri.parse("homeWidget://open"))
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
                
                val syncIntent = HomeWidgetBackgroundIntent.getBroadcast(context, android.net.Uri.parse("homeWidget://sync"))
                views.setOnClickPendingIntent(R.id.btn_sync, syncIntent)
                
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e("NagavalliWidget", "Error updating line widget", e)
            }
        }
    }
}
