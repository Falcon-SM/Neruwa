package com.falcon.neruwa

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import com.falcon.neruwa.data.NeruwaRepository

class NeruwaViewModel(application: Application) : AndroidViewModel(application) {
    val repository = NeruwaRepository(application)
}
