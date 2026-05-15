package lingxue.flsqliteviewer.shizuku;

interface IFlSqlViewerShizukuFileService {
    void destroy();
    List<String> listEntries(String path);
    List<String> listInstalledPackageNames();
    boolean fileExists(String path);
    byte[] readFile(String path);
    void writeFile(String path, in byte[] bytes);
}