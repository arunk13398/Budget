package com.budget.planning

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View

class ChartView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {
    
    private val barPaint = Paint().apply {
        color = Color.parseColor("#2196F3")
        style = Paint.Style.FILL
    }
    
    private val textPaint = Paint().apply {
        color = Color.BLACK
        textSize = 24f
        textAlign = Paint.Align.CENTER
    }
    
    private var data = listOf<Int>()
    private var currentValue = 0
    
    fun setData(newData: List<Int>, current: Int) {
        data = newData
        currentValue = current
        invalidate() // Request redraw
    }
    
    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        
        if (data.isEmpty()) {
            canvas.drawText("No data yet", width / 2f, height / 2f, textPaint)
            return
        }
        
        val maxValue = data.maxOrNull()?.toFloat() ?: 1f
        val barWidth = width.toFloat() / data.size
        val barSpacing = 8f
        val actualBarWidth = barWidth - barSpacing
        
        for (i in data.indices) {
            val barHeight = (data[i] / maxValue) * (height - 60f)
            val left = i * barWidth + barSpacing / 2
            val right = left + actualBarWidth
            val top = height - barHeight - 40f
            val bottom = height - 40f
            
            canvas.drawRect(left, top, right, bottom, barPaint)
        }
        
        textPaint.textSize = 16f
        canvas.drawText("Current: $currentValue", width / 2f, height - 10f, textPaint)
    }
}
