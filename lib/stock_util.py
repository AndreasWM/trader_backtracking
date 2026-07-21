import os
import sys
import csv
import glob
import subprocess
from pathlib import Path

project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

HOME_DIR_LINUX = '/home/andreas/'
HOME_DIR_WINDOWS = '/mnt/c/Users/moell/'
DATA_DIR = 'Downloads/data/'

class StockUtil:
    def detect_ib_host(self) -> str:
        # 1. Check: Läuft das Skript in WSL?
        if "microsoft" in subprocess.check_output("uname -a", shell=True).decode().lower():
            try:
                # Hol die IP des Windows-Hosts (das Gateway)
                cmd = "ip route show | grep default | awk '{print $3}'"
                host_ip = subprocess.check_output(cmd, shell=True).decode().strip()
                if host_ip:
                    return host_ip
            except Exception:
                pass
        
        # 2. Fallback: Wenn echter Ubuntu-PC oder WSL-Erkennung fehlschlägt
        return "127.0.0.1"
        
    def create_text_file(self, text: str, filename: str | Path):
        with open(filename, 'w') as f:
            f.write(text)

    def read_symbols(self, path: str) -> list[str]:
        symbols = []
        
        with open(path, 'r', encoding='utf-8') as datei:
            csv_reader = csv.DictReader(datei)
            
            for line in csv_reader:
                if 'Symbol' in line:
                    symbols.append(line['Symbol'])
        
        return symbols
    
    def _get_home_dir(self) -> str:
        if self.detect_ib_host() == "127.0.0.1":
            return HOME_DIR_LINUX
        else:
            return HOME_DIR_WINDOWS

    def get_data_dir(self) -> str:
        return self._get_home_dir() + DATA_DIR

    def get_latest_file(self, dir: str, pattern: str) -> str:
        pattern = os.path.join(dir, pattern+'*.csv')
        files = glob.glob(pattern)
        
        if not files:
            raise FileNotFoundError(f"Keine Datei mit Muster '{pattern}*.csv' in {dir}")
        
        return max(files, key=os.path.getmtime)
    
    def get_latest_do_not_trade_file(self) -> str:
        return self.get_latest_file(dir=self.get_data_dir(), pattern='DoNotTrade')
    
    def get_latest_watchlist_file(self) -> str:
        return self.get_latest_file(dir=self.get_data_dir(), pattern='Watchlist')
