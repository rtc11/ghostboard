module config;
import raylib5;

struct Config
{
    String config_dir;
    String storage_file;
    String log_file;
    int history_limit;
    String font_path;
    int expire_unused_days;
    int expire_used_days;
}

