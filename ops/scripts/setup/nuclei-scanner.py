#!/usr/bin/env python3
# IDPS Raspberry Pi Nuclei Scanner - Edge Security Component
# Lichtgewicht scanner voor edge deployment op Raspberry Pi

import json
import subprocess
import sys
import os
import requests
from datetime import datetime
from pathlib import Path
import logging
import psutil
import time

class PiNucleiScanner:
    def __init__(self):
        self.api_base_url = os.getenv('API_BASE_URL', 'http://192.168.97.4:8081')
        self.pi_ip = os.getenv('PI_IP', '192.168.107.2')
        self.output_dir = '/opt/idps/pi/scans'
        self.max_cpu_usage = 80  # Max CPU usage for Pi
        self.max_memory_usage = 80  # Max memory usage for Pi
        
        self.setup_logging()
        self.check_system_resources()
        
    def setup_logging(self):
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/var/log/idps/pi/nuclei_scanner.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger('PiNucleiScanner')
        
    def check_system_resources(self):
        """Controleer of Pi voldoende resources heeft"""
        cpu_percent = psutil.cpu_percent(interval=1)
        memory_percent = psutil.virtual_memory().percent
        
        if cpu_percent > self.max_cpu_usage:
            self.logger.warning(f"Hoge CPU gebruik: {cpu_percent}% - scans vertraagd")
            return False
            
        if memory_percent > self.max_memory_usage:
            self.logger.warning(f"Hoog geheugen gebruik: {memory_percent}% - scans uitgesteld")
            return False
            
        self.logger.info(f"System resources OK - CPU: {cpu_percent}%, Memory: {memory_percent}%")
        return True
        
    def scan_local_system(self):
        """Scan lokaal systeem met beperkte scope"""
        if not self.check_system_resources():
            self.logger.warning("Onvoldoende resources - lokale scan overgeslagen")
            return None
            
        self.logger.info("Starten lokale systeem scan")
        
        targets = [
            "localhost",
            "127.0.0.1",
            self.pi_ip
        ]
        
        results = []
        for target in targets:
            try:
                result = self.run_lightweight_scan(target, f"local_{target}")
                if result:
                    results.append(result)
                    self.send_results_to_api(result)
            except Exception as e:
                self.logger.error(f"Lokale scan mislukt voor {target}: {e}")
                
        return results
        
    def scan_internal_network(self):
        """Scan intern netwerk met zeer beperkte scope"""
        if not self.check_system_resources():
            self.logger.warning("Onvoldoende resources - netwerk scan overgeslagen")
            return None
            
        self.logger.info("Starten interne netwerk scan")
        
        # Zeer beperkte netwerk scan voor Pi
        targets = [
            "192.168.107.0/30",  # Alleen directe buren
            "192.168.107.1",      # Gateway
        ]
        
        results = []
        for target in targets:
            try:
                result = self.run_ultra_lightweight_scan(target, f"network_{target.replace('.', '_')}")
                if result:
                    results.append(result)
                    self.send_results_to_api(result)
            except Exception as e:
                self.logger.error(f"Netwerk scan mislukt voor {target}: {e}")
                
        return results
        
    def run_lightweight_scan(self, target, scan_name):
        """Lichtgewicht scan geschikt voor Raspberry Pi"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = f"{self.output_dir}/{scan_name}_{timestamp}.json"
        
        # Zeer conservatieve nuclei configuratie voor Pi
        cmd = [
            "nuclei",
            "-target", target,
            "-json",
            "-silent",
            "-no-color",
            "-rate-limit", "2",  # Zeer laag voor Pi
            "-timeout", "15",
            "-retries", "1",
            "-c", "2",  # Max 2 concurrent
            "-t", "cve/",
            "-exclude", "exposure",  # Geen exposure scans
            "-exclude", "misconfiguration",  # Geen config scans
            "-o", output_file
        ]
        
        try:
            self.logger.info(f"Starten lightweight scan: {target}")
            start_time = time.time()
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=1800  # 30 minuten max
            )
            
            end_time = time.time()
            scan_duration = end_time - start_time
            
            if result.returncode == 0:
                findings = self.process_json_output(output_file)
                pi_findings = self.filter_pi_findings(findings)
                
                return {
                    'scan_name': scan_name,
                    'target': target,
                    'scan_type': 'lightweight_local',
                    'timestamp': timestamp,
                    'findings_count': len(pi_findings),
                    'findings': pi_findings,
                    'output_file': output_file,
                    'scan_duration_seconds': scan_duration,
                    'pi_resources': {
                        'cpu_usage_before': psutil.cpu_percent(),
                        'memory_usage_before': psutil.virtual_memory().percent
                    }
                }
            else:
                self.logger.error(f"Lightweight scan mislukt: {result.stderr}")
                return None
                
        except subprocess.TimeoutExpired:
            self.logger.error(f"Lightweight scan timeout: {scan_name}")
            return None
        except Exception as e:
            self.logger.error(f"Lightweight scan fout: {e}")
            return None
            
    def run_ultra_lightweight_scan(self, target, scan_name):
        """Ultra lichtgewicht scan voor netwerk discovery"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = f"{self.output_dir}/{scan_name}_{timestamp}.json"
        
        # Minimale nuclei configuratie
        cmd = [
            "nuclei",
            "-target", target,
            "-json",
            "-silent",
            "-no-color",
            "-rate-limit", "1",  # Minimaal
            "-timeout", "10",
            "-c", "1",  # Single thread
            "-t", "technologies/",  # Alleen tech detection
            "-o", output_file
        ]
        
        try:
            self.logger.info(f"Starten ultra-lightweight scan: {target}")
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=600  # 10 minuten max
            )
            
            if result.returncode == 0:
                findings = self.process_json_output(output_file)
                pi_findings = self.filter_pi_findings(findings)
                
                return {
                    'scan_name': scan_name,
                    'target': target,
                    'scan_type': 'ultra_lightweight_network',
                    'timestamp': timestamp,
                    'findings_count': len(pi_findings),
                    'findings': pi_findings,
                    'output_file': output_file,
                    'pi_optimized': True
                }
            else:
                self.logger.error(f"Ultra-lightweight scan mislukt: {result.stderr}")
                return None
                
        except subprocess.TimeoutExpired:
            self.logger.error(f"Ultra-lightweight scan timeout: {scan_name}")
            return None
        except Exception as e:
            self.logger.error(f"Ultra-lightweight scan fout: {e}")
            return None
            
    def filter_pi_findings(self, findings):
        """Filter findings geschikt voor Pi context"""
        pi_findings = []
        
        for finding in findings:
            # Alleen laag-risico findings voor Pi
            if finding.get('ernst') in ['Laag', 'Informatief']:
                pi_findings.append(finding)
            elif finding.get('ernst') == 'Middel':
                # Beperkt aantal middelbare risico's
                if len([f for f in pi_findings if f.get('ernst') == 'Middel']) < 3:
                    pi_findings.append(finding)
                    
        return pi_findings
        
    def process_json_output(self, json_file):
        """Verwerk Nuclei JSON output"""
        findings = []
        
        try:
            with open(json_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            finding = json.loads(line)
                            translated = self.translate_finding(finding)
                            if translated:
                                findings.append(translated)
                        except json.JSONDecodeError:
                            continue
        except FileNotFoundError:
            self.logger.error(f"Output file niet gevonden: {json_file}")
            
        return findings
        
    def translate_finding(self, finding):
        """Vertaal finding voor Pi context"""
        if 'info' not in finding:
            return None
            
        info = finding['info']
        
        severity_map = {
            'critical': 'Kritiek',
            'high': 'Hoog', 
            'medium': 'Middel',
            'low': 'Laag',
            'info': 'Informatief'
        }
        
        return {
            'id': finding.get('template-id', ''),
            'kwetsbaarheid': info.get('name', 'Onbekend'),
            'ernst': severity_map.get(info.get('severity', 'unknown'), 'Onbekend'),
            'target': finding.get('host', ''),
            'beschrijving': info.get('description', ''),
            'impact_op_provil_ion': self.assess_pi_impact(finding),
            'actieplan': self.generate_pi_action_plan(finding),
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'pi_optimized': True
        }
        
    def assess_pi_impact(self, finding):
        """Beoordeel impact specifiek voor Pi edge device"""
        info = finding.get('info', {})
        name = info.get('name', '').lower()
        
        if 'local' in name or 'localhost' in name:
            return "Middel - Kan lokale Pi beveiliging beïnvloeden"
        elif 'network' in name or 'router' in name:
            return "Laag - Netwerk discovery, geen direct risico"
        elif 'service' in name or 'daemon' in name:
            return "Laag - Service detectie, monitoringswaarde"
        else:
            return "Laag - Informatieve waarde voor edge monitoring"
            
    def generate_pi_action_plan(self, finding):
        """Genereer actieplan voor Pi context"""
        info = finding.get('info', {})
        name = info.get('name', '').lower()
        
        if 'local' in name:
            return "1. Controleer lokale service\n2. Update indien nodig\n3. Monitor gedrag"
        elif 'network' in name:
            return "1. Documenteer netwerk device\n2. Monitor voor veranderingen\n3. Rapporteer aan beheer"
        else:
            return "1. Toevoegen aan inventory\n2. Periodiek controleren\n3. Update bij wijzigingen"
            
    def send_results_to_api(self, scan_result):
        """Stuur resultaten naar centrale API"""
        try:
            response = requests.post(
                f"{self.api_base_url}/vulnerabilities/pi-scan-results",
                json=scan_result,
                timeout=30
            )
            
            if response.status_code == 200:
                self.logger.info(f"Pi scan resultaten opgeslagen: {scan_result['scan_name']}")
            else:
                self.logger.error(f"Opslaan Pi scan resultaten mislukt: {response.status_code}")
                
        except Exception as e:
            self.logger.error(f"Fout bij opslaan Pi scan resultaten: {e}")
            
    def get_pi_status(self):
        """Krijg Pi status en resource gebruik"""
        return {
            'cpu_usage': psutil.cpu_percent(interval=1),
            'memory_usage': psutil.virtual_memory().percent,
            'disk_usage': psutil.disk_usage('/').percent,
            'temperature': self.get_pi_temperature(),
            'uptime': time.time() - psutil.boot_time(),
            'load_average': os.getloadavg()[0] if hasattr(os, 'getloadavg') else 0
        }
        
    def get_pi_temperature(self):
        """Krijg Raspberry Pi temperatuur"""
        try:
            with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                temp = int(f.read().strip()) / 1000.0
                return temp
        except:
            return None
            
    def generate_pi_report(self):
        """Genereer Pi specifiek rapport"""
        self.logger.info("Genereren Pi rapport")
        
        status = self.get_pi_status()
        
        report = {
            'report_type': 'pi_scan',
            'timestamp': datetime.now().isoformat(),
            'component': 'raspberry-pi',
            'pi_status': status,
            'scan_capabilities': {
                'lightweight_scan': True,
                'network_scan': True,
                'resource_monitoring': True,
                'max_cpu_usage': self.max_cpu_usage,
                'max_memory_usage': self.max_memory_usage
            },
            'optimization_features': {
                'rate_limiting': True,
                'resource_aware': True,
                'pi_optimized_templates': True,
                'minimal_disruption': True
            }
        }
        
        # Stuur rapport naar API
        try:
            response = requests.post(
                f"{self.api_base_url}/vulnerabilities/pi-report",
                json=report,
                timeout=30
            )
            
            if response.status_code == 200:
                self.logger.info("Pi rapport opgeslagen")
            else:
                self.logger.error(f"Pi rapport opslaan mislukt: {response.status_code}")
                
        except Exception as e:
            self.logger.error(f"Fout bij opslaan Pi rapport: {e}")
            
        return report

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='IDPS Raspberry Pi Nuclei Scanner')
    parser.add_argument('--scan-local', action='store_true', help='Scan lokaal systeem')
    parser.add_argument('--scan-network', action='store_true', help='Scan intern netwerk')
    parser.add_argument('--pi-report', action='store_true', help='Genereer Pi rapport')
    parser.add_argument('--status', action='store_true', help='Toon Pi status')
    parser.add_argument('--all', action='store_true', help='Voer alle functies uit')
    
    args = parser.parse_args()
    
    scanner = PiNucleiScanner()
    
    if args.status:
        status = scanner.get_pi_status()
        print(f"Pi Status:")
        print(f"  CPU: {status['cpu_usage']:.1f}%")
        print(f"  Memory: {status['memory_usage']:.1f}%")
        print(f"  Disk: {status['disk_usage']:.1f}%")
        if status['temperature']:
            print(f"  Temperature: {status['temperature']:.1f}°C")
        return
    
    if args.all or args.pi_report:
        scanner.generate_pi_report()
    
    if args.all or args.scan_local:
        scanner.scan_local_system()
        
    if args.all or args.scan_network:
        scanner.scan_internal_network()

if __name__ == "__main__":
    main()
