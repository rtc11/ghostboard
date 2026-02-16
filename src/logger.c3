module logger;
import std::io;
import std::os::macos::objc;
import std::os::env;
import std::core::log;
import std::time;
import config;

struct StdoutLogger (Logger) {
	void* dummy;
}

fn void StdoutLogger.log(&self, LogPriority priority, LogCategory category, LogTag tag, String file, String function, int line, String fmt, any[] args) @dynamic {
    @pool() {
        TzDateTime time = datetime::now().to_local();
        DString str;
        str.tinit(256);
        defer str.free();
        str.appendf(fmt, ...args);
        io::printfn("[%02d:%02d:%02d] [%s] %s", time.hour, time.min, time.sec, priority, str.str_view());
    };
}

struct FileLogger (log::Logger) {
    File file;
}

fn void FileLogger.log(&self, log::LogPriority priority, log::LogCategory category, log::LogTag tag, String file, String function, int line, String fmt, any[] args) @dynamic {
    @pool() {
        TzDateTime time = datetime::now().to_local();
        DString str;
        str.tinit(256);
        defer str.free();
        str.appendf("[%02d:%02d:%02d] [%s] ", time.hour, time.min, time.sec, priority);
        str.appendf(fmt, ...args);
        str.append_char('\n');
        if (catch io::write_all(&self.file, str.str_view())) return;
        (void)self.file.flush();
    };
}

fn void setup_logging(Config* config) {
    // Check if we're running as a .app bundle
    ObjcId bundle = objc::msg_send(objc::getClass("NSBundle"), SendVoid, "mainBundle");
    ObjcId bundle_path = objc::msg_send(bundle, SendVoid, "bundlePath");
    bool is_app_bundle = false;
    if (bundle_path != null) {
        ZString path_str = (ZString)objc::msg_send(bundle_path, SendVoid, "UTF8String");
        String path = path_str.str_view();
        is_app_bundle = path.contains(".app");
    }
    
    if (is_app_bundle) {
        // Running as .app - log to file only
        String? home = env::tget_var("HOME");
        if (catch home) {
            io::eprintfn("ERROR: could not get HOME directory");
            return;
        }
        String dir_path = string::tformat("%s/%s", home, config.config_dir);
        io::path::mkdir(dir_path, true)!!;
        String log_path = string::tformat("%s/%s", dir_path, config.log_file);
        
        File? file = file::open(log_path, "ab");
        if (catch excuse = file) {
            io::eprintfn("ERROR: could not open log file: %s", excuse);
            return;
        }
        
        FileLogger* file_logger = mem::new(FileLogger);
        file_logger.file = file;
        log::set_logger(file_logger);
    } else {
        // Running from terminal - log to both stdout and file
        String? home = env::tget_var("HOME");
        if (try home) {
            String dir_path = string::tformat("%s/%s", home, config.config_dir);
            io::path::mkdir(dir_path, true)!!;
            String log_path = string::tformat("%s/%s", dir_path, config.log_file);
            
            File? file = file::open(log_path, "ab");
            if (try file) {
                FileLogger* file_logger = mem::new(FileLogger);
                file_logger.file = file;
                
                StdoutLogger* stdout_logger = mem::new(StdoutLogger);
                
                log::Logger[] loggers = mem::new_array(log::Logger, 2);
                loggers[0] = file_logger;
                loggers[1] = stdout_logger;
                
                log::MultiLogger* multi = mem::new(log::MultiLogger);
                multi.loggers = loggers;
                log::set_logger(multi);
            }
        }
    }
    
    log::set_priority_all(INFO);
    log::info("=== GhostBoard started ===");
}

