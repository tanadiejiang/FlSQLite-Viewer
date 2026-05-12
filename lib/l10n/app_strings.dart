import 'package:flutter/material.dart';

class AppStrings {
  AppStrings(this.languageCode);

  final String languageCode;

  static String _currentLanguageCode = 'zh';

  static void updateCurrentLanguageCode(String languageCode) {
    _currentLanguageCode = languageCode;
  }

  static AppStrings get current => AppStrings(_currentLanguageCode);

  static AppStrings of(BuildContext context) {
    return AppStrings(Localizations.localeOf(context).languageCode);
  }

  bool get isZh => languageCode.toLowerCase().startsWith('zh');

  Locale get locale => Locale(isZh ? 'zh' : 'en');

  String get appName => 'FlSQLite Viewer';
  String get settings => isZh ? '设置' : 'Settings';
  String get recentRecordsCleared =>
      isZh ? '已清空最近打开记录' : 'Recent records cleared';
  String get language => isZh ? '语言' : 'Language';
  String get chinese => isZh ? '中文' : 'Chinese';
  String get english => isZh ? '英文' : 'English';
  String get back => isZh ? '返回' : 'Back';
  String get viewDetailsAction => isZh ? '查看详情' : 'View details';
  String get anyType => isZh ? '任意' : 'Any';
  String get fileBrowser => isZh ? '文件浏览器' : 'File Browser';
  String get advancedAccess => isZh ? '高级访问' : 'Advanced Access';
  String get addRow => isZh ? '新增行' : 'Add Row';
  String get minimizeWindow => isZh ? '最小化' : 'Minimize';
  String get maximizeOrRestoreWindow => isZh ? '最大化/还原' : 'Maximize/Restore';
  String get closeWindow => isZh ? '关闭' : 'Close';
  String get homeSubtitle => isZh
      ? '跨平台 SQLite 数据库查看与编辑器'
      : 'Cross-platform SQLite database viewer and editor';
  String get openDatabase => isZh ? '打开数据库' : 'Open Database';
  String get androidAdvancedAccessSettings =>
      isZh ? 'Android 高级访问设置' : 'Android Advanced Access Settings';
  String get recentOpen => isZh ? '最近打开' : 'Recent Open';
  String get supportedAccessTypes =>
      isZh ? '支持的访问方式' : 'Supported Access Types';
  String get desktopOpenHint =>
      isZh ? '支持直接拖入或手动打开' : 'Drag files in or open manually';
  String get normalDirectoryAccess =>
      isZh ? '普通目录访问' : 'Normal Directory Access';
  String get allFilesAccess => isZh ? '全部文件访问' : 'All Files Access';
  String get rootMode => isZh ? 'Root 模式 (su)' : 'Root Mode (su)';
  String get shizukuAccess => isZh ? 'Shizuku 授权访问' : 'Shizuku Access';
  String get changesSavedToSource =>
      isZh ? '更改已保存到源文件' : 'Changes saved to source file';
  String get databaseClosed => isZh ? '数据库已关闭' : 'Database closed';
  String get unsavedChangesTitle => isZh ? '有未保存修改' : 'Unsaved Changes';
  String get unsavedChangesContent =>
      isZh ? '是否先保存当前修改再返回？' : 'Save current changes before going back?';
  String get saveBeforeOpenNewFileContent => isZh
      ? '是否保存当前修改，然后打开新文件？'
      : 'Save current changes before opening the new file?';
  String get yes => isZh ? '是' : 'Yes';
  String get no => isZh ? '否' : 'No';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get discard => isZh ? '不保存' : 'Discard';
  String get saveAndBack => isZh ? '保存并返回' : 'Save and Back';
  String get discardedUnsavedChanges =>
      isZh ? '已放弃未保存修改' : 'Unsaved changes discarded';
  String openedPath(String path) => isZh ? '已打开: $path' : 'Opened: $path';
  String reopenedName(String name) => isZh ? '已重新打开: $name' : 'Reopened: $name';
  String get recentDeleteTitle => isZh ? '删除最近打开记录' : 'Delete Recent Record';
  String deleteRecentContent(String name) =>
      isZh ? '确定删除 $name 这条最近打开记录吗？' : 'Delete recent record "$name"?';
  String deletedRecent(String name) =>
      isZh ? '已删除最近打开记录: $name' : 'Deleted recent record: $name';
  String get rowAddedPendingSave =>
      isZh ? '已新增行，待保存到源文件' : 'Row added, pending save to source file';
  String get rowUpdatedPendingSave =>
      isZh ? '已更新行，待保存到源文件' : 'Row updated, pending save to source file';
  String get confirmDelete => isZh ? '确认删除' : 'Confirm Delete';
  String get confirmDeleteRowContent => isZh
      ? '确定要删除这行数据吗？此操作不可撤销。'
      : 'Delete this row? This action cannot be undone.';
  String get rowDeletedPendingSave =>
      isZh ? '已删除行，待保存到源文件' : 'Row deleted, pending save to source file';
  String openFailed(Object error) =>
      isZh ? '打开失败: $error' : 'Open failed: $error';
  String get modeAllFiles => isZh ? '全部文件' : 'All Files';
  String get modeRoot => 'Root';
  String get modeShizuku => 'Shizuku';
  String get modeNormal => isZh ? '普通' : 'Normal';

  String formatRelativeTime(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) {
      return isZh ? '刚刚' : 'Just now';
    }
    if (difference.inHours < 1) {
      return isZh
          ? '${difference.inMinutes}分钟前'
          : '${difference.inMinutes} min ago';
    }
    if (difference.inDays < 1) {
      return isZh ? '${difference.inHours}小时前' : '${difference.inHours} hr ago';
    }
    if (difference.inDays < 30) {
      return isZh ? '${difference.inDays}天前' : '${difference.inDays} days ago';
    }
    if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return isZh ? '$months个月前' : '$months months ago';
    }
    final years = (difference.inDays / 365).floor();
    return isZh ? '$years年前' : '$years years ago';
  }

  String selectedCount(int count) => isZh ? '已选择 $count 项' : '$count selected';
  String get exitSelection => isZh ? '退出多选' : 'Exit selection';
  String get multiSelect => isZh ? '多选' : 'Multi-select';
  String get deleteSelected => isZh ? '删除所选' : 'Delete selected';
  String get clearRecords => isZh ? '清空记录' : 'Clear records';
  String get noRecentRecords => isZh ? '暂无最近打开记录' : 'No recent records';
  String get clearRecentTitle => isZh ? '清空最近打开' : 'Clear Recent Records';
  String get clearRecentContent =>
      isZh ? '确定清空全部最近打开记录吗？' : 'Clear all recent records?';
  String get clear => isZh ? '清空' : 'Clear';
  String deleteSelectedTitle(int count) => count == 1
      ? (isZh ? '删除最近打开记录' : 'Delete Recent Record')
      : (isZh ? '删除所选记录' : 'Delete Selected Records');
  String deleteSelectedContent(int count, String name) => count == 1
      ? (isZh ? '确定删除 $name 这条最近打开记录吗？' : 'Delete recent record "$name"?')
      : (isZh
            ? '确定删除选中的 $count 条最近打开记录吗？'
            : 'Delete $count selected recent records?');
  String deletedRecentCount(int count) =>
      isZh ? '已删除 $count 条最近打开记录' : 'Deleted $count recent records';

  String get androidAdvancedAccessTitle =>
      isZh ? 'Android 高级访问' : 'Android Advanced Access';
  String get androidAdvancedAccessIntro => isZh
      ? '启用高级访问模式后，您可以通过特殊的文件访问通道打开受保护或受限目录中的 SQLite 数据库文件。授权状态与是否参与访问链已分离：即使已授权，关闭开关后也不会使用该通道。'
      : 'After enabling advanced access, you can open SQLite databases in protected or restricted directories through special file access channels. Authorization state is separate from whether a channel participates in the access chain: even if authorized, a disabled channel will not be used.';
  String get shizukuAuthorized => isZh ? 'Shizuku 已授权' : 'Shizuku authorized';
  String get shizukuUnauthorized =>
      isZh ? 'Shizuku 未授权' : 'Shizuku not authorized';
  String get securityNotice => isZh ? '安全提示' : 'Security Notice';
  String get securityNoticeContent => isZh
      ? 'Root 和 Shizuku 模式具有系统级权限。\n仅在您完全了解风险的情况下启用。\n修改应用私有数据可能导致该应用工作异常或数据丢失。'
      : 'Root and Shizuku modes have system-level privileges.\nEnable them only if you fully understand the risks.\nModifying private app data may break the target app or cause data loss.';
  String get refreshAllStatuses => isZh ? '刷新所有状态' : 'Refresh All Statuses';

  String get accessManageAllFilesLabel => isZh ? '全部文件访问' : 'All Files Access';
  String get accessManageAllFilesDescription =>
      isZh ? '允许访问外部存储中的任意文件' : 'Allows access to any file in external storage';
  String get accessRootLabel => isZh ? 'Root 模式' : 'Root Mode';
  String get accessRootDescription =>
      isZh ? '通过 su 访问受保护的路径' : 'Access protected paths through su';
  String get accessShizukuLabel => isZh ? 'Shizuku 模式' : 'Shizuku Mode';
  String get accessShizukuDescription => isZh
      ? '通过 Shizuku 访问受限目录'
      : 'Access restricted directories through Shizuku';
  String get authorized => isZh ? '已授权' : 'Authorized';
  String get unauthorized => isZh ? '未授权' : 'Unauthorized';
  String get rootAvailable => isZh ? 'Root 可用' : 'Root available';
  String get rootUnavailable => isZh ? 'Root 不可用' : 'Root unavailable';
  String get shizukuNotInstalled =>
      isZh ? '未安装 Shizuku' : 'Shizuku not installed';
  String get shizukuNotRunning => isZh ? 'Shizuku 未运行' : 'Shizuku not running';
  String get enabledInAccessChain => isZh
      ? '当前已启用，会参与文件访问降级链。'
      : 'Enabled and will participate in the access fallback chain.';
  String get authorizedButDisabled => isZh
      ? '已授权，但当前不会使用此访问通道。'
      : 'Authorized, but this access channel is currently disabled.';
  String get enabledButUnavailable =>
      isZh ? '已开启使用，但当前状态不可用。' : 'Enabled, but currently unavailable.';
  String get currentlyDisabled => isZh ? '当前未启用。' : 'Currently disabled.';
  String get openSystemSettings => isZh ? '打开系统设置' : 'Open System Settings';
  String get checkRootStatus => isZh ? '检测 Root 状态' : 'Check Root Status';
  String get requestShizukuPermission =>
      isZh ? '请求 Shizuku 授权' : 'Request Shizuku Permission';
  String get rootUnavailableOrDisabled =>
      isZh ? 'Root 权限无/或未启用' : 'Root unavailable or disabled';
  String get shizukuUnavailableOrDisabled =>
      isZh ? 'Shizuku 权限无/或未启用' : 'Shizuku unavailable or disabled';
  String get allFilesUnavailableOrDisabled =>
      isZh ? '全部文件访问无/或未启用' : 'All Files Access unavailable or disabled';
  String get normalAccessUnavailable =>
      isZh ? '普通目录访问不可用' : 'Normal directory access unavailable';
  String get listDirectoryAction => isZh ? '列出目录' : 'List directory';
  String get openDatabaseAction => isZh ? '打开数据库' : 'Open database';
  String get restrictedDirectoryNeedPrivileged => isZh
      ? '该目录受 Android 限制，全部文件访问不足以访问，请启用 Shizuku 或 Root'
      : 'This directory is restricted by Android. All Files Access is not enough; enable Shizuku or Root.';
  String get restrictedDirectoryStillFailed => isZh
      ? '该目录受 Android 限制，已尝试 Shizuku 或 Root，但当前仍无法访问'
      : 'This directory is restricted by Android. Shizuku or Root was tried, but access still failed.';
  String get restrictedDatabaseNeedPrivileged => isZh
      ? '该数据库位于 Android 受限目录，请使用 Shizuku 或 Root 访问'
      : 'This database is in a restricted Android directory. Use Shizuku or Root to access it.';
  String get restrictedDirectoryNeedShizukuOrRoot => isZh
      ? '该目录位于 Android 受限区域，请使用 Shizuku 或 Root 访问'
      : 'This directory is in a restricted Android area. Use Shizuku or Root to access it.';
  String actionFailed(String action, String path) =>
      isZh ? '$action失败: $path' : '$action failed: $path';

  String get rootTestPath => isZh ? 'Root 测试路径' : 'Root Test Path';
  String get shizukuTestPath => isZh ? 'Shizuku 测试路径' : 'Shizuku Test Path';
  String get backupDirectory => isZh ? '普通/备份目录' : 'Normal/Backup Directory';

  String get fileBrowserTitle => isZh ? '文件浏览器' : 'File Browser';
  String get filterFilesHint =>
      isZh ? '过滤文件/目录...' : 'Filter files/directories...';
  String get showDatabasesOnly => isZh ? '仅显示数据库' : 'Databases only';
  String get goUp => isZh ? '上一级' : 'Up';
  String get directoryLoadFailed => isZh ? '目录加载失败' : 'Directory load failed';
  String get viewDetails => isZh ? '查看详情' : 'View details';
  String get retry => isZh ? '重试' : 'Retry';
  String get noFilterMatches =>
      isZh ? '当前筛选无匹配项' : 'No matches for current filter';
  String get noDatabaseFiles =>
      isZh ? '当前目录无数据库文件' : 'No database files in current directory';
  String get directoryEmpty => isZh ? '目录为空' : 'Directory is empty';

  String get databaseNotOpen => isZh ? '未打开数据库' : 'Database not open';
  String get noTableSelected => isZh ? '未选择表' : 'No table selected';
  String get noData => isZh ? '无数据' : 'No data';
  String rowsRange(int start, int end, int total) =>
      isZh ? '$start-$end / $total 行' : '$start-$end / $total rows';
  String pageIndicator(int current, int total) =>
      isZh ? '第 $current/$total 页' : 'Page $current/$total';
  String get saving => isZh ? '保存中' : 'Saving';
  String get save => isZh ? '保存' : 'Save';
  String searchTable(String name) => isZh ? '搜索 $name...' : 'Search $name...';
  String get actions => isZh ? '操作' : 'Actions';
  String get details => isZh ? '详情' : 'Details';
  String get edit => isZh ? '编辑' : 'Edit';
  String get delete => isZh ? '删除' : 'Delete';
  String get firstPage => isZh ? '首页' : 'First page';
  String get previousPage => isZh ? '上一页' : 'Previous page';
  String get nextPage => isZh ? '下一页' : 'Next page';
  String get lastPage => isZh ? '末页' : 'Last page';
  String get refresh => isZh ? '刷新' : 'Refresh';

  String get editRow => isZh ? '编辑行' : 'Edit Row';
  String get rowDetails => isZh ? '行详情' : 'Row Details';
  String get saveChanges => isZh ? '保存' : 'Save';
  String get requiredField => isZh ? '必填' : 'Required';
  String fieldCannotBeEmpty(String name) =>
      isZh ? '$name 不能为空' : '$name cannot be empty';
  String get changesSaved => isZh ? '已保存修改' : 'Changes saved';

  String get addRowTitle => isZh ? '新增行' : 'Add Row';
  String get nullLabel => 'NULL';
  String get add => isZh ? '新增' : 'Add';

  String get rowNotFoundForUpdate => isZh
      ? '目标行不存在或已变化，未能更新'
      : 'Target row no longer exists or changed; update failed';
  String get rowNotFoundForDelete => isZh
      ? '目标行不存在或已变化，未能删除'
      : 'Target row no longer exists or changed; delete failed';
}

extension AppStringsBuildContextX on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}
