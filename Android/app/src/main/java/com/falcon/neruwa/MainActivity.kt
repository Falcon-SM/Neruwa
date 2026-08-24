package com.falcon.neruwa

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import com.falcon.neruwa.ui.NeruwaApp
import com.falcon.neruwa.ui.theme.NeruwaTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            NeruwaTheme {
                val viewModel: NeruwaViewModel = viewModel()
                NeruwaApp(repository = viewModel.repository)
            }
        }
    }
}
