package com.falcon.neruwa.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.falcon.neruwa.data.NeruwaRepository
import com.falcon.neruwa.model.DailyPeriod
import com.falcon.neruwa.ui.components.AmbientScreen
import com.falcon.neruwa.ui.screens.DailyFlowScreen
import com.falcon.neruwa.ui.screens.HistoryScreen
import com.falcon.neruwa.ui.screens.LearningScreen
import com.falcon.neruwa.ui.screens.PvtScreen
import com.falcon.neruwa.ui.screens.SettingsScreen
import com.falcon.neruwa.ui.screens.ShareScreen
import com.falcon.neruwa.ui.screens.SleepScreen
import java.time.LocalTime

private enum class AppTab(val label: String) {
    SLEEP("睡眠記録"),
    LEARNING("学習"),
    PVT("PVT"),
    HISTORY("記録"),
    SHARE("共有")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NeruwaApp(repository: NeruwaRepository) {
    var selectedTab by rememberSaveable { mutableStateOf(AppTab.SLEEP) }
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var activeFlow by remember {
        val time = LocalTime.now()
        val period = repository.schedule.periodAt(time.hour, time.minute)
        mutableStateOf(period.takeIf { repository.shouldStartFlow(it) && repository.sleepTimerStartMillis == 0L })
    }

    if (activeFlow != null) {
        DailyFlowScreen(
            period = activeFlow!!,
            repository = repository,
            onCancel = { activeFlow = null },
            onComplete = {
                repository.completeFlow(activeFlow!!)
                activeFlow = null
                selectedTab = AppTab.SLEEP
            },
            onSleepStarted = {
                repository.completeFlow(DailyPeriod.NIGHT)
                activeFlow = null
                selectedTab = AppTab.SLEEP
            }
        )
        return
    }

    AmbientScreen(isNight = true) {
        Scaffold(
            containerColor = androidx.compose.ui.graphics.Color.Transparent,
            topBar = {
                TopAppBar(
                    title = { Text(if (showSettings) "設定" else selectedTab.label) },
                    actions = {
                        IconButton(onClick = { showSettings = !showSettings }) {
                            Icon(Icons.Default.Settings, contentDescription = "設定")
                        }
                    }
                )
            },
            bottomBar = {
                if (!showSettings) {
                    NavigationBar {
                        AppTab.entries.forEach { tab ->
                            NavigationBarItem(
                                selected = selectedTab == tab,
                                onClick = { selectedTab = tab },
                                icon = {
                                    Icon(
                                        imageVector = when (tab) {
                                            AppTab.SLEEP -> Icons.Default.Bedtime
                                            AppTab.LEARNING -> Icons.Default.MenuBook
                                            AppTab.PVT -> Icons.Default.Psychology
                                            AppTab.HISTORY -> Icons.Default.History
                                            AppTab.SHARE -> Icons.Default.Groups
                                        },
                                        contentDescription = tab.label
                                    )
                                },
                                label = { Text(tab.label) }
                            )
                        }
                    }
                }
            }
        ) { padding ->
            val modifier = Modifier.padding(padding)
            if (showSettings) {
                SettingsScreen(
                    repository = repository,
                    modifier = modifier,
                    onStartFlow = {
                        showSettings = false
                        activeFlow = it
                    }
                )
            } else {
                when (selectedTab) {
                    AppTab.SLEEP -> SleepScreen(
                        repository = repository,
                        modifier = modifier,
                        onWake = { activeFlow = DailyPeriod.MORNING }
                    )
                    AppTab.LEARNING -> LearningScreen(repository, modifier)
                    AppTab.PVT -> PvtScreen(repository, modifier)
                    AppTab.HISTORY -> HistoryScreen(repository, modifier)
                    AppTab.SHARE -> ShareScreen(repository, modifier)
                }
            }
        }
    }
}
