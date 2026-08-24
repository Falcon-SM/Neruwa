package com.falcon.neruwa.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

@Composable
fun AmbientScreen(
    modifier: Modifier = Modifier,
    isNight: Boolean = true,
    content: @Composable BoxScope.() -> Unit
) {
    val colors = if (isNight) {
        listOf(Color(0xFF05091E), Color(0xFF0C1640), Color(0xFF06091B))
    } else {
        listOf(Color(0xFF4677A8), Color(0xFF87BFD1), Color(0xFFF2C995))
    }
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Brush.linearGradient(colors)),
        content = {
            Canvas(Modifier.fillMaxSize()) {
                if (isNight) {
                    val stars = listOf(
                        0.08f to 0.10f, 0.19f to 0.26f, 0.36f to 0.08f,
                        0.61f to 0.18f, 0.84f to 0.12f, 0.94f to 0.32f,
                        0.12f to 0.57f, 0.41f to 0.48f, 0.76f to 0.61f,
                        0.27f to 0.78f, 0.56f to 0.88f, 0.91f to 0.82f
                    )
                    stars.forEachIndexed { index, (x, y) ->
                        drawCircle(
                            color = Color.White.copy(alpha = if (index % 3 == 0) 0.56f else 0.30f),
                            radius = if (index % 4 == 0) 3.2f else 2.0f,
                            center = Offset(size.width * x, size.height * y)
                        )
                    }
                }
            }
            content()
        }
    )
}
