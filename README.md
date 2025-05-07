# ⚡ Battery Monitor System - Fedora Edition

A terminal-based **Battery Health & Power Manager** script designed for Fedora Linux. Monitor your laptop’s battery health, power usage, and environmental impact—all in one place.

---

## 📦 Features

| Option | Feature                                | Description                                                                 |
|--------|----------------------------------------|-----------------------------------------------------------------------------|
| `1`    | Battery Info                           | Shows battery percentage, charging status, and current power consumption.  |
| `2`    | Power Category & Profiles              | Lists available power profiles (balanced, performance, power-saver).       |
| `3`    | Battery Health Analysis                | Shows battery health based on design capacity vs full charge capacity.     |
| `4`    | Battery Wear Level                     | Calculates and displays battery wear percentage.                           |
| `5`    | Top Power-Consuming Processes          | Displays top processes consuming battery power using `powerstat`/`top`.    |
| `6`    | CPU & GPU Usage Information            | Real-time CPU and GPU utilization.                                         |
| `7`    | Environmental Impact                   | Estimates CO₂ saved by using battery mode vs plugged-in mode.              |
| `8`    | Enable Power Saving Mode               | Automatically sets low-power mode using `powerprofilesctl`.                |
| `9`    | Start Background Logging               | Logs battery info to a file every minute in the background.                |
| `0`    | Stop Background Logging                | Stops the background logging process.                                      |
| `L`    | Show Log Analysis                      | Displays and analyzes the historical log data.                             |
| `C`    | Configure Settings                     | Configure logging intervals and thresholds.                                |
| `Q`    | Quit                                   | Exit the script.                                                           |

---

## 🛠️ Installation (Fedora Linux)

Follow these steps to install and run the script on Fedora:

### 📥 Clone the Repository

```bash
git clone https://github.com/prajwalshettar43/Battery.git
cd battery-monitor-fedora
```

### 🔐 Make the Script Executable

```bash
chmod +x battery_manager.sh
```

### 🚀 Run the Script

```bash
./battery_manager.sh
```
This project was built using AI assistance from [ChatGPT](https://chat.openai.com) and [Claude AI](https://claude.ai/).
