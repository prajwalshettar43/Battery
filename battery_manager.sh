#!/bin/bash

# Enhanced Battery & Power Manager for Fedora 42
# This script provides comprehensive battery and power management information

# Check for required commands and packages
check_dependencies() {
    local missing_deps=()
    
    for cmd in upower bc awk grep ps free df; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "\e[31mMissing dependencies: ${missing_deps[*]}\e[0m"
        echo -e "Install them with: sudo dnf install ${missing_deps[*]}"
        exit 1
    fi
}

# Configuration file
CONFIG_FILE="$HOME/.config/power_manager.conf"
LOG_FILE="$HOME/.local/share/power_manager/battery_log.csv"

# Create necessary directories
mkdir -p "$HOME/.config"
mkdir -p "$HOME/.local/share/power_manager"

# Load or create configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "# Power Manager Configuration" > "$CONFIG_FILE"
        echo "LOG_INTERVAL=300" >> "$CONFIG_FILE"  # Default to 5 minutes
        echo "POWER_SAVING_THRESHOLD=25" >> "$CONFIG_FILE"  # Battery percentage
        echo "NOTIFICATIONS=true" >> "$CONFIG_FILE"
        echo "AUTO_POWER_SAVING=true" >> "$CONFIG_FILE"
    fi
    
    source "$CONFIG_FILE"
}

# Battery Info
get_battery_info() {
    echo -e "\n🔋 \e[1mBattery Info:\e[0m"

    # Find all batteries in the system
    batteries=$(upower -e | grep battery)
    if [ -z "$batteries" ]; then
        echo "No battery detected."
        return 1
    fi

    # Process each battery
    battery_count=0
    for battery in $batteries; do
        battery_count=$((battery_count + 1))
        echo -e "\e[1mBattery #$battery_count\e[0m"
        
        info=$(upower -i "$battery")
        
        # Extract battery information
        vendor=$(echo "$info" | grep -E "vendor" | awk '{$1=""; print $0}' | xargs)
        model=$(echo "$info" | grep -E "model" | awk '{$1=""; print $0}' | xargs)
        tech=$(echo "$info" | grep -E "technology" | awk '{$1=""; print $0}' | xargs)
        percent=$(echo "$info" | grep -E "percentage" | awk '{print $2}' | sed 's/%//')
        state=$(echo "$info" | grep -E "state:" | awk '{print $2}')
        energy=$(echo "$info" | grep -E "energy:" | awk '{print $2 " " $3}')
        energy_full=$(echo "$info" | grep -E "energy-full:" | awk '{print $2 " " $3}')
        energy_design=$(echo "$info" | grep -E "energy-full-design:" | awk '{print $2 " " $3}')
        
        # Calculate health percentage
        if [[ "$energy_full" && "$energy_design" ]]; then
            energy_full_val=$(echo "$energy_full" | awk '{print $1}')
            energy_design_val=$(echo "$energy_design" | awk '{print $1}')
            health=$(echo "scale=2; 100 * $energy_full_val / $energy_design_val" | bc)
        else
            health="N/A"
        fi
        
        # Time remaining info
        if [[ "$state" == "discharging" ]]; then
            time_remaining=$(echo "$info" | grep -E "time to empty" | awk -F ":" '{print $2":"$3}' | xargs)
            [ -z "$time_remaining" ] && time_remaining="Calculating..."
        elif [[ "$state" == "charging" ]]; then
            time_remaining=$(echo "$info" | grep -E "time to full" | awk -F ":" '{print $2":"$3}' | xargs)
            [ -z "$time_remaining" ] && time_remaining="Calculating..."
        else
            time_remaining="N/A"
        fi
        
        # Power usage
        power=$(echo "$info" | grep "energy-rate" | awk '{print $2}')
        units=$(echo "$info" | grep "energy-rate" | awk '{print $3}')
        
        # Check if power data is available
        if [ -z "$power" ]; then
            power="N/A"
            units=""
            usage_level="Unknown"
        else
            if (( $(echo "$power > 12" | bc -l) )); then
                usage_level="🔥 \e[31mHigh Usage\e[0m"
            elif (( $(echo "$power > 7" | bc -l) )); then
                usage_level="⚠️ \e[33mModerate Usage\e[0m"
            else
                usage_level="✅ \e[32mLow Usage\e[0m"
            fi
        fi
        
        # Create battery bar
        if [ -n "$percent" ]; then
            bars=$((percent / 10))
            visual=$(printf '█%.0s' $(seq 1 $bars))
            remaining_space=$((10 - bars))
            if [ $remaining_space -gt 0 ]; then
                empty=$(printf '░%.0s' $(seq 1 $remaining_space))
                visual="$visual$empty"
            fi
            
            # Color-code based on percentage
            if [ "$percent" -le 10 ]; then
                bar_color="\e[31m"  # Red for critical
            elif [ "$percent" -le 25 ]; then
                bar_color="\e[33m"  # Yellow for low
            else
                bar_color="\e[32m"  # Green for good
            fi
            
            visual="${bar_color}${visual}\e[0m"
        else
            visual="N/A"
            percent="N/A"
        fi
        
        # Display adapter status
        adapter_status=$(echo "$info" | grep "online" | awk '{print $2}')
        [ "$adapter_status" = "yes" ] && adapter_status="Connected" || adapter_status="Not Connected"

        # Display the collected information
        [ -n "$vendor" ] && echo -e "  Vendor: $vendor"
        [ -n "$model" ] && echo -e "  Model: $model"
        [ -n "$tech" ] && echo -e "  Technology: $tech"
        echo -e "  ⚡ State: $state"
        echo -e "  🔋 Charge: ${percent}% [$visual]"
        [ "$time_remaining" != "N/A" ] && echo -e "  ⏳ Time ${state/discharging/Remaining}: $time_remaining"
        echo -e "  🔌 Adapter: $adapter_status"
        echo -e "  🧭 Power Use: $usage_level ($power $units)"
        echo -e "  🔋 Health: ${health}%"
        echo -e "  💾 Capacity: $energy / $energy_full (Design: $energy_design)"
        echo ""
    done
    
    return 0
}

# Show Power Category based on system power profile
show_power_category() {
    echo -e "\n⚡ \e[1mPower Category:\e[0m"
    
    # Check if power-profiles-daemon is available
    if command -v powerprofilesctl &> /dev/null; then
        current_profile=$(powerprofilesctl get)
        echo -e "  Current Power Profile: \e[1m$current_profile\e[0m"
        
        # Get available profiles more reliably
        echo -e "  Available profiles:"
        profiles=("power-saver" "balanced" "performance")
        for profile in "${profiles[@]}"; do
            if [[ "$profile" == "$current_profile" ]]; then
                echo -e "    - $profile (current)"
            else
                echo -e "    - $profile"
            fi
        done
        
        # Offer to change profile
        echo ""
        echo -e "  Change profile? (y/n): "
        read -r change_profile
        
        if [[ "$change_profile" == "y" ]]; then
            echo -e "  Enter profile name (power-saver, balanced, performance): "
            read -r new_profile
            
            # Validate input with exact matching
            if [[ "$new_profile" == "power-saver" || "$new_profile" == "balanced" || "$new_profile" == "performance" ]]; then
                powerprofilesctl set "$new_profile"
                echo -e "  Profile changed to: $new_profile"
            else
                echo -e "  \e[31mInvalid profile name. Must be one of: power-saver, balanced, performance\e[0m"
            fi
        fi
    else
        echo "  Power profiles daemon not available."
        echo "  Install with: sudo dnf install power-profiles-daemon"
        
        # Fallback to TLP if available
        if command -v tlp-stat &> /dev/null; then
            tlp_status=$(tlp-stat -s | grep "Mode" | awk '{print $3}')
            echo -e "  TLP Power Mode: $tlp_status"
        fi
    fi
    
    # Better check for power source with multiple possibilities
    power_source="Unknown"
    
    # Try different possible paths for AC adapter status
    for adapter in /sys/class/power_supply/*/online; do
        if [ -f "$adapter" ]; then
            on_battery=$(cat "$adapter" 2>/dev/null || echo "Unknown")
            if [ "$on_battery" == "0" ]; then
                power_source="Battery"
                break
            elif [ "$on_battery" == "1" ]; then
                power_source="AC"
                break
            fi
        fi
    done
    
    # Display power source
    if [ "$power_source" == "Battery" ]; then
        echo -e "  🔋 Running on battery power"
    elif [ "$power_source" == "AC" ]; then
        echo -e "  🔌 Running on AC power"
    else
        echo -e "  Power source information unavailable"
    fi
}

# Battery Health Analysis
show_battery_health() {
    echo -e "\n🩺 \e[1mBattery Health Analysis:\e[0m"
    
    # Find all batteries
    batteries=$(upower -e | grep battery)
    if [ -z "$batteries" ]; then
        echo "No battery detected."
        return
    fi
    
    for battery in $batteries; do
        info=$(upower -i "$battery")
        
        # Extract data for health analysis
        energy_full=$(echo "$info" | grep -E "energy-full:" | awk '{print $2}')
        energy_design=$(echo "$info" | grep -E "energy-full-design:" | awk '{print $2}')
        
        if [[ "$energy_full" && "$energy_design" ]]; then
            health=$(echo "scale=2; 100 * $energy_full / $energy_design" | bc)
            
            # Determine health status
            if (( $(echo "$health >= 80" | bc -l) )); then
                health_status="Excellent"
                stars="★★★★★"
                color="\e[32m"
            elif (( $(echo "$health >= 60" | bc -l) )); then
                health_status="Good"
                stars="★★★★☆"
                color="\e[32m"
            elif (( $(echo "$health >= 40" | bc -l) )); then
                health_status="Fair"
                stars="★★★☆☆"
                color="\e[33m"
            elif (( $(echo "$health >= 20" | bc -l) )); then
                health_status="Poor"
                stars="★★☆☆☆"
                color="\e[33m"
            else
                health_status="Critical"
                stars="★☆☆☆☆"
                color="\e[31m"
            fi
            
            echo -e "  Battery Health: ${color}${health}%\e[0m (${health_status})"
            echo -e "  Health Rating: ${color}${stars}\e[0m"
            
            # Give recommendations based on health
            echo -e "\n  Recommendations:"
            if (( $(echo "$health < 60" | bc -l) )); then
                echo -e "  • Consider battery replacement in the near future"
            fi
            if (( $(echo "$health < 80" | bc -l) )); then
                echo -e "  • Avoid full discharge cycles"
                echo -e "  • Keep battery between 20% and 80% for optimal longevity"
            fi
            echo -e "  • Avoid exposing your laptop to extreme temperatures"
            echo -e "  • Use original charger when possible"
        else
            echo -e "  Battery health information unavailable"
        fi
    done
}

# Background Logging
log_running=false
log_pid=""

start_background_logging() {
    echo -e "\n🔴 \e[1mStarting Background Logging...\e[0m"
    
    # Create log header if file doesn't exist
    if [ ! -f "$LOG_FILE" ]; then
        echo "Timestamp,Battery,Percentage,State,Energy,Power_Usage,Health" > "$LOG_FILE"
    fi
    
    # Check if already logging
    if [ "$log_running" = true ]; then
        echo "  Logging is already running with PID: $log_pid"
        return
    fi
    
    # Start background logging
    (
        while true; do
            batteries=$(upower -e | grep battery)
            timestamp=$(date "+%Y-%m-%d %H:%M:%S")
            
            for battery in $batteries; do
                info=$(upower -i "$battery")
                batt_name=$(basename "$battery")
                percent=$(echo "$info" | grep -E "percentage" | awk '{print $2}' | sed 's/%//')
                state=$(echo "$info" | grep -E "state:" | awk '{print $2}')
                energy=$(echo "$info" | grep -E "energy:" | awk '{print $2}')
                power=$(echo "$info" | grep "energy-rate" | awk '{print $2}')
                
                # Calculate health
                energy_full=$(echo "$info" | grep -E "energy-full:" | awk '{print $2}')
                energy_design=$(echo "$info" | grep -E "energy-full-design:" | awk '{print $2}')
                
                if [[ "$energy_full" && "$energy_design" ]]; then
                    health=$(echo "scale=2; 100 * $energy_full / $energy_design" | bc)
                else
                    health="N/A"
                fi
                
                # Log the data
                echo "$timestamp,$batt_name,$percent,$state,$energy,$power,$health" >> "$LOG_FILE"
            done
            
            sleep "$LOG_INTERVAL"
        done
    ) &
    
    log_pid=$!
    log_running=true
    
    echo "  Logging started with PID: $log_pid"
    echo "  Log file: $LOG_FILE"
    echo "  Logging interval: $LOG_INTERVAL seconds"
}

stop_background_logging() {
    echo -e "\n🔴 \e[1mStopping Background Logging...\e[0m"
    
    if [ "$log_running" = true ] && [ -n "$log_pid" ]; then
        kill "$log_pid" 2>/dev/null
        log_running=false
        log_pid=""
        echo "  Logging stopped"
    else
        echo "  No active logging process found"
    fi
}

# Show Log
show_log() {
    echo -e "\n📝 \e[1mLog Analysis:\e[0m"
    
    if [ ! -f "$LOG_FILE" ]; then
        echo "  No logs found. Start logging first."
        return
    fi
    
    # Count log entries
    log_entries=$(wc -l < "$LOG_FILE")
    log_entries=$((log_entries - 1))  # Subtract header line
    
    echo -e "  Total log entries: $log_entries"
    echo -e "  Log file: $LOG_FILE"
    
    # Menu for log options
    echo -e "\n  Log options:"
    echo "  1. Show recent entries"
    echo "  2. Show statistics"
    echo "  3. Export to CSV"
    echo "  4. Clear log"
    echo "  5. Back"
    echo -n "  Choose an option: "
    read -r log_option
    
    case $log_option in
        1)
            echo -e "\n  Recent log entries (last 10):"
            if [ "$log_entries" -gt 0 ]; then
                head -n 1 "$LOG_FILE"  # Show header
                tail -n 10 "$LOG_FILE" | column -t -s ','
            else
                echo "  No entries in log"
            fi
            ;;
        2)
            echo -e "\n  Log Statistics:"
            if [ "$log_entries" -gt 0 ]; then
                # Calculate average battery percentage
                avg_percent=$(tail -n +2 "$LOG_FILE" | awk -F ',' '{sum+=$3; count++} END {print sum/count}')
                # Find min battery percentage
                min_percent=$(tail -n +2 "$LOG_FILE" | awk -F ',' '{if(min=="" || $3<min) min=$3} END {print min}')
                # Calculate discharge rate
                avg_power=$(tail -n +2 "$LOG_FILE" | awk -F ',' '{if($4=="discharging") {sum+=$6; count++}} END {if(count>0) print sum/count; else print "N/A"}')
                
                echo "  Average battery level: $(printf "%.1f" "$avg_percent")%"
                echo "  Minimum recorded level: $min_percent%"
                echo "  Average discharge rate: $(if [[ "$avg_power" != "N/A" ]]; then printf "%.2f" "$avg_power"; else echo "$avg_power"; fi) W"
            else
                echo "  No entries in log"
            fi
            ;;
        3)
            export_file="$HOME/battery_export_$(date +%Y%m%d_%H%M%S).csv"
            cp "$LOG_FILE" "$export_file"
            echo -e "\n  Log exported to: $export_file"
            ;;
        4)
            echo -e "\n  Are you sure you want to clear the log? (y/n): "
            read -r confirm
            if [[ "$confirm" == "y" ]]; then
                # Keep the header but remove all data
                head -n 1 "$LOG_FILE" > "${LOG_FILE}.new"
                mv "${LOG_FILE}.new" "$LOG_FILE"
                echo "  Log cleared"
            else
                echo "  Clear operation cancelled"
            fi
            ;;
        5)
            return
            ;;
        *)
            echo "  Invalid option"
            ;;
    esac
}

# CO₂ Saved Calculation based on power usage
show_co2_saved() {
    echo -e "\n🌍 \e[1mEnvironmental Impact:\e[0m"
    
    # Get battery info
    batteries=$(upower -e | grep battery)
    if [ -z "$batteries" ]; then
        echo "  No battery detected."
        return
    fi
    
    # Constants for calculation
    # Average CO2 emission from power plants (kg CO2 per kWh)
    # This varies by country and power source
    CO2_PER_KWH=0.475  # Global average
    
    total_power_usage=0
    total_energy_saved=0
    
    for battery in $batteries; do
        info=$(upower -i "$battery")
        
        # Check if on battery or AC
        state=$(echo "$info" | grep -E "state:" | awk '{print $2}')
        
        if [[ "$state" == "discharging" ]]; then
            # Extract current power usage
            power=$(echo "$info" | grep "energy-rate" | awk '{print $2}')
            
            if [ -n "$power" ]; then
                total_power_usage=$(echo "$total_power_usage + $power" | bc)
                
                # Calculate potential saved energy if in power saving mode
                # Assume 20% power reduction in power saving mode
                potential_saved=$(echo "scale=3; $power * 0.2" | bc)
                total_energy_saved=$(echo "$total_energy_saved + $potential_saved" | bc)
            fi
        fi
    done
    
    # Calculate CO2 emissions saved over an hour
    if [ -n "$total_energy_saved" ] && [ "$total_energy_saved" != "0" ]; then
        hourly_co2_saved=$(echo "scale=3; $total_energy_saved * $CO2_PER_KWH / 1000" | bc)
        daily_co2_saved=$(echo "scale=3; $hourly_co2_saved * 24" | bc)
        
        echo -e "  Current Power Usage: ${total_power_usage}W"
        echo -e "  Potential Power Saved in Power Saving Mode: ${total_energy_saved}W"
        echo -e "  Estimated CO₂ Saved per Hour: ${hourly_co2_saved} kg"
        echo -e "  Estimated CO₂ Saved per Day: ${daily_co2_saved} kg"
        echo -e "  Equivalent to: $(echo "scale=1; $daily_co2_saved / 0.00892" | bc) km not driven in an average car"
    else
        echo -e "  Not currently discharging or power data unavailable"
    fi
    
    # Eco tips
    echo -e "\n  🌱 Eco Tips:"
    echo -e "  • Use power saving mode when on battery"
    echo -e "  • Reduce screen brightness to save power"
    echo -e "  • Close unused applications and browser tabs"
    echo -e "  • Consider using dark mode themes when possible"
}

# Show Battery Wear Level
show_wear_level() {
    echo -e "\n🧳 \e[1mBattery Wear Analysis:\e[0m"
    
    batteries=$(upower -e | grep battery)
    if [ -z "$batteries" ]; then
        echo "  No battery detected."
        return
    fi
    
    for battery in $batteries; do
        info=$(upower -i "$battery")
        
        energy_full=$(echo "$info" | grep -E "energy-full:" | awk '{print $2}')
        energy_design=$(echo "$info" | grep -E "energy-full-design:" | awk '{print $2}')
        
        if [[ "$energy_full" && "$energy_design" ]]; then
            wear_level=$(echo "scale=2; 100 - 100 * $energy_full / $energy_design" | bc)
            
            # Determine wear status
            if (( $(echo "$wear_level <= 5" | bc -l) )); then
                wear_status="Excellent"
                color="\e[32m"
            elif (( $(echo "$wear_level <= 15" | bc -l) )); then
                wear_status="Good"
                color="\e[32m"
            elif (( $(echo "$wear_level <= 30" | bc -l) )); then
                wear_status="Fair"
                color="\e[33m"
            elif (( $(echo "$wear_level <= 50" | bc -l) )); then
                wear_status="Poor"
                color="\e[33m"
            else
                wear_status="Critical"
                color="\e[31m"
            fi
            
            # Calculate capacity retention
            capacity_retention=$(echo "scale=2; 100 - $wear_level" | bc)
            
            echo -e "  Battery Wear Level: ${color}${wear_level}%\e[0m (${wear_status})"
            echo -e "  Capacity Retention: ${color}${capacity_retention}%\e[0m"
            echo -e "  Original Capacity: ${energy_design} Wh"
            echo -e "  Current Capacity: ${energy_full} Wh"
            
            # Calculate estimated charge cycles
            # This is a rough estimate as we don't have direct cycle count
            estimated_cycles=$(echo "scale=0; $wear_level * 20 / 10" | bc)  # Very rough estimation
            echo -e "  Estimated Battery Cycles: ~${estimated_cycles} cycles"
            
            # Check battery age if available
            if [ -d "/sys/class/power_supply" ]; then
                bat_path=$(find /sys/class/power_supply -name "BAT*" -o -name "*battery*" | head -n 1)
                if [ -n "$bat_path" ]; then
                    manufacture_date=$(cat "$bat_path/manufacture_date" 2>/dev/null || echo "")
                    if [ -n "$manufacture_date" ]; then
                        echo -e "  Manufacture Date: $manufacture_date"
                    fi
                fi
            fi
            
            # Provide recommendations
            echo -e "\n  Recommendations:"
            if (( $(echo "$wear_level > 30" | bc -l) )); then
                echo -e "  • Consider battery replacement for optimal performance"
            fi
            if (( $(echo "$wear_level > 15" | bc -l) )); then
                echo -e "  • Avoid full charge/discharge cycles"
                echo -e "  • Keep battery between 20% and 80% when possible"
            fi
            echo -e "  • Avoid exposing your laptop to extreme temperatures"
        else
            echo -e "  Battery wear information unavailable"
        fi
    done
}

# Show Top Power Consuming Processes
show_top_power_processes() {
    echo -e "\n🧾 \e[1mTop Power-Hungry Processes:\e[0m"
    
    # Check if powertop is available
    if command -v powertop &> /dev/null; then
        echo -e "  PowerTOP available - running detailed power analysis..."
        echo -e "  This might take a few seconds..."
        
        # Create a temporary file for powertop output
        tmp_file=$(mktemp)
        
        # Run powertop in CSV mode to get power consumption data
        sudo powertop --csv="$tmp_file" --time=5 2>/dev/null
        
        if [ -f "$tmp_file" ]; then
            echo -e "\n  Top power consumers (from PowerTOP):"
            grep -A 20 "Process Device" "$tmp_file" | grep -v "Process Device" | head -n 10 | awk -F';' '{print "  " $2 " - " $3}' | sort -u
            rm "$tmp_file"
        else
            echo -e "  Failed to get PowerTOP data. Falling back to CPU usage..."
            fallback_to_cpu=true
        fi
    else
        echo -e "  PowerTOP not available. Install with: sudo dnf install powertop"
        echo -e "  Falling back to CPU usage as an indicator for power consumption..."
        fallback_to_cpu=true
    fi
    
    # Fallback to CPU usage as indicator
    if [ "$fallback_to_cpu" = true ]; then
        echo -e "\n  Top CPU-consuming processes (indicator of power usage):"
        ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%cpu | head -n 11 | awk 'NR>1 {printf "  %5s %5s %5.1f%% %5.1f%% %s\n", $1, $2, $4, $5, $3}' | 
        awk '{printf "  %-5s %5s %5s %5s  %s\n", $1, $2, $3, $4, substr($0, index($0,$5))}'
    fi
    
    echo -e "\n  Power-saving tips:"
    echo -e "  • Close unused applications, especially those with high CPU/GPU usage"
    echo -e "  • Reduce browser tabs, especially those with animations or videos"
    echo -e "  • Disable unnecessary background services and startup applications"
    echo -e "  • Consider using lighter alternatives for resource-intensive applications"
}

# Show CPU & GPU Usage with thermal info
show_cpu_gpu_usage() {
    echo -e "\n💻 \e[1mCPU & GPU Usage:\e[0m"
    
    # Get CPU info
    cpu_model=$(grep "model name" /proc/cpuinfo | head -n 1 | cut -d ':' -f 2 | xargs)
    cpu_cores=$(grep -c "processor" /proc/cpuinfo)
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    
    echo -e "  CPU Model: $cpu_model"
    echo -e "  CPU Cores: $cpu_cores"
    echo -e "  CPU Usage: ${cpu_usage}%"
    
    # CPU frequency info
    if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
        current_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
        max_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null)
        min_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 2>/dev/null)
        governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
        
        if [ -n "$current_freq" ] && [ -n "$max_freq" ]; then
            current_freq_ghz=$(echo "scale=2; $current_freq / 1000000" | bc)
            max_freq_ghz=$(echo "scale=2; $max_freq / 1000000" | bc)
            min_freq_ghz=$(echo "scale=2; $min_freq / 1000000" | bc)
            
            echo -e "  CPU Frequency: ${current_freq_ghz} GHz (Range: ${min_freq_ghz}-${max_freq_ghz} GHz)"
            [ -n "$governor" ] && echo -e "  CPU Governor: $governor"
        fi
    fi
    
    # CPU temperature
    if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
        cpu_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        if [ -n "$cpu_temp" ]; then
            cpu_temp=$(echo "scale=1; $cpu_temp / 1000" | bc)
            
            # Color-code based on temperature
            if (( $(echo "$cpu_temp >= 80" | bc -l) )); then
                temp_color="\e[31m"  # Red for hot
            elif (( $(echo "$cpu_temp >= 60" | bc -l) )); then
                temp_color="\e[33m"  # Yellow for warm
            else
                temp_color="\e[32m"  # Green for cool
            fi
            
            echo -e "  CPU Temperature: ${temp_color}${cpu_temp}°C\e[0m"
        fi
    fi
    
# GPU info - NVIDIA
if command -v nvidia-smi &> /dev/null; then
    echo -e "\n  NVIDIA GPU Information:"
    gpu_info=$(nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,power.draw --format=csv,noheader,nounits)
    gpu_name=$(echo "$gpu_info" | awk -F, '{print $1}')
    gpu_util=$(echo "$gpu_info" | awk -F, '{print $2}')
    gpu_temp=$(echo "$gpu_info" | awk -F, '{print $3}')
    gpu_power=$(echo "$gpu_info" | awk -F, '{print $4}')
    
    echo -e "  GPU Model: $gpu_name"
    echo -e "  GPU Utilization: ${gpu_util}%"
    echo -e "  GPU Temperature: ${gpu_temp}°C"
    echo -e "  GPU Power Draw: ${gpu_power}W"
elif command -v glxinfo &> /dev/null; then
    # Alternative for AMD/Intel GPUs
    gpu_info=$(glxinfo | grep "OpenGL renderer")
    gpu_name=$(echo "$gpu_info" | sed 's/OpenGL renderer string: //')
    echo -e "\n  GPU Information:"
    echo -e "  GPU Model: $gpu_name"
else
    echo -e "\n  GPU information unavailable"
fi

# Memory information
mem_info=$(free -h | grep "Mem:")
mem_total=$(echo "$mem_info" | awk '{print $2}')
mem_used=$(echo "$mem_info" | awk '{print $3}')
mem_usage_percent=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | xargs printf "%.1f")

echo -e "\n  Memory Usage: ${mem_usage_percent}% (${mem_used} of ${mem_total})"

# Disk information
disk_info=$(df -h / | tail -n 1)
disk_total=$(echo "$disk_info" | awk '{print $2}')
disk_used=$(echo "$disk_info" | awk '{print $3}')
disk_usage_percent=$(echo "$disk_info" | awk '{print $5}')

echo -e "  Disk Usage: ${disk_usage_percent} (${disk_used} of ${disk_total})"
}

# Power Saving Mode
enable_power_saving() {
    echo -e "\n🔋 \e[1mEnabling Power Saving Mode:\e[0m"
    
    # Check if we can control power profile using power-profiles-daemon
    if command -v powerprofilesctl &> /dev/null; then
        # Set power-saver profile
        powerprofilesctl set power-saver
        echo -e "  Power profile set to: power-saver"
    # Check if we can use tuned instead
    elif command -v tuned-adm &> /dev/null; then
        # Set powersave profile with tuned
        sudo tuned-adm profile powersave
        echo -e "  Tuned profile set to: powersave"
    else
        echo -e "  No power profile manager detected."
    fi
    
    # CPU frequency scaling - this works on most Linux systems
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        if [ -f "$cpu" ]; then
            echo "powersave" | sudo tee "$cpu" > /dev/null
        fi
    done
    echo -e "  CPU governor set to powersave"
    
    # Suggested system tweaks
    echo -e "\n  Additional power saving tips:"
    echo -e "  • Close unused applications and browser tabs"
    echo -e "  • Reduce screen brightness manually"
    echo -e "  • Disconnect unused peripherals"
    echo -e "  • Disable Wi-Fi/Bluetooth if not needed"
}

# Display main menu
show_menu() {
    clear
    echo -e "\e[1;34m================================\e[0m"
    echo -e "\e[1;34m  Battery & Power Manager v1.0  \e[0m"
    echo -e "\e[1;34m================================\e[0m"
    echo -e "Fedora 42 Edition"
    echo -e "Date: $(date +"%Y-%m-%d %H:%M:%S")"
    
    # Check battery status
    get_battery_info
    
    # Show menu
    echo -e "\n📋 \e[1mOptions:\e[0m"
    echo -e "  1. Battery Info"
    echo -e "  2. Power Category & Profiles"
    echo -e "  3. Battery Health Analysis"
    echo -e "  4. Battery Wear Level"
    echo -e "  5. Top Power-Consuming Processes"
    echo -e "  6. CPU & GPU Usage Information"
    echo -e "  7. Environmental Impact"
    echo -e "  8. Enable Power Saving Mode"
    echo -e "  9. Start Background Logging"
    echo -e "  0. Stop Background Logging"
    echo -e "  L. Show Log Analysis"
    echo -e "  C. Configure Settings"
    echo -e "  Q. Quit"
    echo -e "\n  Choose an option: "
}

# Configure settings
configure_settings() {
    echo -e "\n⚙️ \e[1mConfiguration Settings:\e[0m"
    echo -e "  Current settings:"
    echo -e "  1. Log Interval: $LOG_INTERVAL seconds"
    echo -e "  2. Power Saving Threshold: $POWER_SAVING_THRESHOLD%"
    echo -e "  3. Notifications: $NOTIFICATIONS"
    echo -e "  4. Auto Power Saving: $AUTO_POWER_SAVING"
    echo -e "  5. Return to main menu"
    echo -e "\n  Choose setting to change: "
    read -r setting_option
    
    case $setting_option in
        1)
            echo -e "  Enter new log interval in seconds (current: $LOG_INTERVAL): "
            read -r new_interval
            if [[ "$new_interval" =~ ^[0-9]+$ ]]; then
                sed -i "s/LOG_INTERVAL=.*/LOG_INTERVAL=$new_interval/" "$CONFIG_FILE"
                echo "  Log interval updated"
                LOG_INTERVAL=$new_interval
            else
                echo "  Invalid input. Must be a number."
            fi
            ;;
        2)
            echo -e "  Enter new power saving threshold percentage (current: $POWER_SAVING_THRESHOLD): "
            read -r new_threshold
            if [[ "$new_threshold" =~ ^[0-9]+$ ]] && [ "$new_threshold" -ge 0 ] && [ "$new_threshold" -le 100 ]; then
                sed -i "s/POWER_SAVING_THRESHOLD=.*/POWER_SAVING_THRESHOLD=$new_threshold/" "$CONFIG_FILE"
                echo "  Power saving threshold updated"
                POWER_SAVING_THRESHOLD=$new_threshold
            else
                echo "  Invalid input. Must be a number between 0 and 100."
            fi
            ;;
        3)
            echo -e "  Enable notifications? (true/false, current: $NOTIFICATIONS): "
            read -r new_notifications
            if [[ "$new_notifications" == "true" || "$new_notifications" == "false" ]]; then
                sed -i "s/NOTIFICATIONS=.*/NOTIFICATIONS=$new_notifications/" "$CONFIG_FILE"
                echo "  Notifications setting updated"
                NOTIFICATIONS=$new_notifications
            else
                echo "  Invalid input. Must be true or false."
            fi
            ;;
        4)
            echo -e "  Enable auto power saving? (true/false, current: $AUTO_POWER_SAVING): "
            read -r new_auto_power
            if [[ "$new_auto_power" == "true" || "$new_auto_power" == "false" ]]; then
                sed -i "s/AUTO_POWER_SAVING=.*/AUTO_POWER_SAVING=$new_auto_power/" "$CONFIG_FILE"
                echo "  Auto power saving setting updated"
                AUTO_POWER_SAVING=$new_auto_power
            else
                echo "  Invalid input. Must be true or false."
            fi
            ;;
        5)
            return
            ;;
        *)
            echo "  Invalid option"
            ;;
    esac
}

# Main program
main() {
    # Check dependencies
    check_dependencies
    
    # Load configuration
    load_config
    
    # Main loop
    while true; do
        show_menu
        read -r option
        
        case $option in
            1)
                get_battery_info
                ;;
            2)
                show_power_category
                ;;
            3)
                show_battery_health
                ;;
            4)
                show_wear_level
                ;;
            5)
                show_top_power_processes
                ;;
            6)
                show_cpu_gpu_usage
                ;;
            7)
                show_co2_saved
                ;;
            8)
                enable_power_saving
                ;;
            9)
                start_background_logging
                ;;
            0)
                stop_background_logging
                ;;
            [Ll])
                show_log
                ;;
            [Cc])
                configure_settings
                ;;
            [Qq])
                echo -e "\nExiting Power Manager. Goodbye!"
                # Clean up before exit
                [ "$log_running" = true ] && stop_background_logging
                exit 0
                ;;
            *)
                echo -e "\nInvalid option. Press Enter to continue..."
                read -r
                ;;
        esac
        
        # Check if auto power saving needs to be enabled
        if [ "$AUTO_POWER_SAVING" = true ]; then
            batteries=$(upower -e | grep battery)
            for battery in $batteries; do
                info=$(upower -i "$battery")
                percent=$(echo "$info" | grep -E "percentage" | awk '{print $2}' | sed 's/%//')
                state=$(echo "$info" | grep -E "state:" | awk '{print $2}')
                
                if [[ "$state" == "discharging" && "$percent" -le "$POWER_SAVING_THRESHOLD" ]]; then
                    echo -e "\n⚠️ Battery below threshold ($percent%). Enabling power saving mode..."
                    enable_power_saving
                    break
                fi
            done
        fi
        
        echo -e "\nPress Enter to continue..."
        read -r
    done
}

# Start the program
main
