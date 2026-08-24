package com.falcon.neruwa.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val NightColorScheme = darkColorScheme(
    primary = Color(0xFF91A7FF),
    onPrimary = Color(0xFF07112F),
    primaryContainer = Color(0xFF26366B),
    secondary = Color(0xFFFFE58F),
    tertiary = Color(0xFF7ED6A5),
    background = Color(0xFF05091E),
    surface = Color(0xFF151A2C),
    surfaceVariant = Color(0xFF23283A),
    onSurface = Color(0xFFF5F6FF),
    onSurfaceVariant = Color(0xFFB9BDD0),
    error = Color(0xFFFF8A8A)
)

@Composable
fun NeruwaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = NightColorScheme,
        typography = MaterialTheme.typography,
        content = content
    )
}
