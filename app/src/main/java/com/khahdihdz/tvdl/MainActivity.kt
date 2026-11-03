package com.khahdihdz.tvdl

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Link
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val shared = when (intent?.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_VIEW -> intent.dataString
            else -> null
        }
        setContent { TvdlScreen(initialUrl = shared.orEmpty()) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TvdlScreen(initialUrl: String) {
    val context = LocalContext.current
    var url by remember { mutableStateOf(initialUrl) }
    var status by remember { mutableStateOf("Dán liên kết hoặc chia sẻ URL vào TVDL.") }

    MaterialTheme {
        Scaffold(topBar = {
            TopAppBar(title = {
                Column {
                    Text("TVDL", fontWeight = FontWeight.Bold)
                    Text("Video Downloader", style = MaterialTheme.typography.labelSmall)
                }
            })
        }) { padding ->
            Column(
                modifier = Modifier.fillMaxSize().padding(padding).padding(20.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Tải video nhanh", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        Text("Nhập URL tải trực tiếp hoặc dùng chức năng Chia sẻ từ ứng dụng khác.")
                    }
                }
                OutlinedTextField(
                    value = url,
                    onValueChange = { url = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Đường dẫn video") },
                    leadingIcon = { androidx.compose.material3.Icon(Icons.Default.Link, contentDescription = null) },
                    minLines = 2
                )
                Button(
                    onClick = {
                        status = enqueueDirectDownload(context, url)
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = url.trim().startsWith("https://") || url.trim().startsWith("http://")
                ) {
                    androidx.compose.material3.Icon(Icons.Default.Download, contentDescription = null)
                    Spacer(Modifier.padding(4.dp))
                    Text("Tải xuống")
                }
                Card {
                    Column(Modifier.padding(16.dp)) {
                        Text("Trạng thái", fontWeight = FontWeight.SemiBold)
                        Spacer(Modifier.height(6.dp))
                        Text(status)
                    }
                }
                Text("Nguồn dự án: YouTube · Facebook · Instagram · X · Xiaohongshu",
                    style = MaterialTheme.typography.bodySmall)
                Text(
                    "Lưu ý: bản Android nền tảng ban đầu hiện hỗ trợ URL tải trực tiếp qua Android Download Manager. Bộ phân tích liên kết và trích xuất media cho từng nền tảng sẽ được tích hợp ở các bản tiếp theo; không phải mọi URL trang video đều là URL tải trực tiếp.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

private fun enqueueDirectDownload(context: Context, rawUrl: String): String {
    val uri = runCatching { Uri.parse(rawUrl.trim()) }.getOrNull()
        ?: return "URL không hợp lệ."
    if (uri.scheme !in listOf("http", "https") || uri.host.isNullOrBlank()) {
        return "Chỉ chấp nhận URL HTTP hoặc HTTPS hợp lệ."
    }
    return runCatching {
        val filename = uri.lastPathSegment?.takeIf { it.contains('.') } ?: "tvdl-download"
        val request = DownloadManager.Request(uri)
            .setTitle(filename)
            .setDescription("Đang tải bằng TVDL")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, filename)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        manager.enqueue(request)
        "Đã đưa tác vụ vào hàng đợi tải xuống. Kiểm tra thông báo Android để theo dõi."
    }.getOrElse { "Không thể bắt đầu tải: ${it.localizedMessage ?: "lỗi không xác định"}" }
}
