#!/usr/bin/env python3
# IDPS Brain-VPS Nuclei Scanner - Educational Network Component
# Gespecialiseerd in het scannen van educatieve netwerken

import json
import subprocess
import sys
import os
import requests
from datetime import datetime, timedelta
from pathlib import Path
import logging
import ipaddress

class BrainNucleiScanner:
    def __init__(self):
        self.api_base_url = os.getenv('API_BASE_URL', 'http://192.168.97.4:8081')
        self.output_dir = '/opt/idps/brain/scans'
        self.educational_networks = [
            '10.0.0.0/16',      # Hoofddoel: educatief netwerk
            '172.16.0.0/12',     # Alternatief educatief bereik
            '192.168.0.0/16',   # Lokale netwerken
        ]
        self.school_domains = [
            'provil-ion.be',
            'www.provil-ion.be',
            'student.provil-ion.be',
            'leerkracht.provil-ion.be'
        ]
        self.safe_scan_hours = range(22, 24) + range(0, 6)  # 22:00-06:00
        
        self.setup_logging()
        
    def setup_logging(self):
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/var/log/idps/brain/nuclei_scanner.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger('BrainNucleiScanner')
        
    def is_safe_scan_time(self):
        """Controleer of het een veilig tijdstip is voor scans"""
        current_hour = datetime.now().hour
        return current_hour in self.safe_scan_hours
        
    def validate_educational_target(self, target):
        """Valideer dat target binnen educatief bereik valt"""
        try:
            # Controleer of het een IP netwerk is
            if '/' in target:
                network = ipaddress.ip_network(target, strict=False)
                for edu_network in self.educational_networks:
                    edu_net = ipaddress.ip_network(edu_network)
                    if network.overlaps(edu_net):
                        return True
                        
            # Controleer school domeinen
            elif any(domain in target for domain in self.school_domains):
                return True
                
            return False
        except Exception as e:
            self.logger.error(f"Target validatie fout: {e}")
            return False
            
    def scan_educational_networks(self):
        """Scan educatieve netwerken met beveiligingen"""
        if not self.is_safe_scan_time():
            self.logger.warning("Scan buiten veilige uren - overgeslagen")
            return None
            
        self.logger.info("Starten educatieve netwerk scan")
        
        results = []
        for network in self.educational_networks:
            try:
                result = self.run_safe_educational_scan(network)
                if result:
                    results.append(result)
                    self.send_results_to_api(result)
            except Exception as e:
                self.logger.error(f"Educatieve scan mislukt voor {network}: {e}")
                
        return results
        
    def scan_school_domains(self):
        """Scan school domeinen op kwetsbaarheden"""
        if not self.is_safe_scan_time():
            self.logger.warning("Domein scan buiten veilige uren - overgeslagen")
            return None
            
        self.logger.info("Starten school domein scan")
        
        results = []
        for domain in self.school_domains:
            try:
                result = self.run_safe_domain_scan(domain)
                if result:
                    results.append(result)
                    self.send_results_to_api(result)
            except Exception as e:
                self.logger.error(f"Domein scan mislukt voor {domain}: {e}")
                
        return results
        
    def run_safe_educational_scan(self, network):
        """Veilige scan van educatief netwerk"""
        if not self.validate_educational_target(network):
            self.logger.warning(f"Target niet gevalideerd voor educatieve scan: {network}")
            return None
            
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        scan_name = f"educational_{network.replace('/', '_')}_{timestamp}"
        output_file = f"{self.output_dir}/{scan_name}.json"
        
        # Zeer veilige nuclei configuratie voor schoolomgeving
        cmd = [
            "nuclei",
            "-target", network,
            "-json",
            "-silent",
            "-no-color",
            "-rate-limit", "5",  # Zeer laag voor schoolnetwerk
            "-timeout", "60",
            "-retries", "1",
            "-t", "cve/",
            "-t", "exposure/",
            "-t", "technologies/",
            # Geen misconfiguration scans op productie systemen
            "-exclude", "misconfiguration",
            "-o", output_file
        ]
        
        try:
            self.logger.info(f"Starten educatieve scan: {network}")
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=3600  # 1 uur timeout
            )
            
            if result.returncode == 0:
                findings = self.process_json_output(output_file)
                # Filter extra veilig voor schoolomgeving
                safe_findings = self.filter_educational_findings(findings)
                
                return {
                    'scan_name': scan_name,
                    'target': network,
                    'scan_type': 'educational_network',
                    'timestamp': timestamp,
                    'findings_count': len(safe_findings),
                    'findings': safe_findings,
                    'output_file': output_file,
                    'safe_scan_time': True
                }
            else:
                self.logger.error(f"Educatieve scan mislukt: {result.stderr}")
                return None
                
        except subprocess.TimeoutExpired:
            self.logger.error(f"Educatieve scan timeout: {scan_name}")
            return None
        except Exception as e:
            self.logger.error(f"Educatieve scan fout: {e}")
            return None
            
    def run_safe_domain_scan(self, domain):
        """Veilige scan van school domein"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        scan_name = f"domain_{domain.replace('.', '_')}_{timestamp}"
        output_file = f"{self.output_dir}/{scan_name}.json"
        
        cmd = [
            "nuclei",
            "-target", domain,
            "-json",
            "-silent",
            "-no-color",
            "-rate-limit", "3",  # Nog lager voor domeinen
            "-timeout", "30",
            "-t", "cve/",
            "-t", "exposure/",
            "-t", "technologies/",
            "-o", output_file
        ]
        
        try:
            self.logger.info(f"Starten domein scan: {domain}")
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=1800  # 30 minuten
            )
            
            if result.returncode == 0:
                findings = self.process_json_output(output_file)
                safe_findings = self.filter_educational_findings(findings)
                
                return {
                    'scan_name': scan_name,
                    'target': domain,
                    'scan_type': 'school_domain',
                    'timestamp': timestamp,
                    'findings_count': len(safe_findings),
                    'findings': safe_findings,
                    'output_file': output_file,
                    'safe_scan_time': True
                }
            else:
                self.logger.error(f"Domein scan mislukt: {result.stderr}")
                return None
                
        except subprocess.TimeoutExpired:
            self.logger.error(f"Domein scan timeout: {scan_name}")
            return None
        except Exception as e:
            self.logger.error(f"Domein scan fout: {e}")
            return None
            
    def filter_educational_findings(self, findings):
        """Extra filter voor educatieve omgeving"""
        safe_findings = []
        
        dangerous_patterns = [
            'exploit',
            'rce',
            'injection',
            'takeover',
            'bypass',
            'privilege escalation'
        ]
        
        for finding in findings:
            # Controleer op gevaarlijke patronen
            description = finding.get('beschrijving', '').lower()
            name = finding.get('kwetsbaarheid', '').lower()
            
            is_safe = True
            for pattern in dangerous_patterns:
                if pattern in description or pattern in name:
                    is_safe = False
                    self.logger.info(f"Gevaarlijke finding gefilterd: {name}")
                    break
                    
            if is_safe and finding.get('ernst') != 'Kritiek':
                safe_findings.append(finding)
                
        return safe_findings
        
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
        """Vertaal finding voor educatieve context"""
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
            'impact_op_provil_ion': self.assess_educational_impact(finding),
            'actieplan': self.generate_educational_action_plan(finding),
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'educational_context': True
        }
        
    def assess_educational_impact(self, finding):
        """Beoordeel impact specifiek voor educatieve omgeving"""
        info = finding.get('info', {})
        name = info.get('name', '').lower()
        tags = info.get('tags', [])
        
        # Educatieve specifieke impact analyse
        if any(keyword in name for keyword in ['student', 'grade', 'attendance']):
            return "Kritiek - Directe impact op leerlinggegevens"
        elif any(keyword in name for keyword in ['teacher', 'staff', 'admin']):
            return "Hoog - Impact op personeelssystemen"
        elif any(keyword in name for keyword in ['network', 'wifi', 'router']):
            return "Middel - Kan netwerk beschikbaarheid beïnvloeden"
        elif any(keyword in name for keyword in ['website', 'portal', 'lms']):
            return "Middel - Kan leerplatform beïnvloeden"
        else:
            return "Laag - Beperkte impact op educatieve processen"
            
    def generate_educational_action_plan(self, finding):
        """Genereer actieplan voor educatieve context"""
        info = finding.get('info', {})
        name = info.get('name', '').lower()
        
        if 'student' in name:
            return "1. Onmiddellijk ICT-beheer waarschuwen\n2. Leerlinggegevens back-uppen\n3. Externe expert inschakelen"
        elif 'network' in name:
            return "1. Buiten schooluren herstellen\n2. Communicatie naar leerlingen/ouders\n3. Alternatieve lessen voorbereiden"
        elif 'ssl' in name or 'tls' in name:
            return "1. Certificaten buiten schooluren vernieuwen\n2. Test met leerkrachten\n3. Communicatie naar beheer"
        else:
            return "1. Plan oplossing in onderhoudsvenster\n2. Minimaliseer lesverstoring\n3. Communiceer tijdig naar team"
            
    def send_results_to_api(self, scan_result):
        """Stuur resultaten naar centrale API"""
        try:
            response = requests.post(
                f"{self.api_base_url}/vulnerabilities/scan-results",
                json=scan_result,
                timeout=60
            )
            
            if response.status_code == 200:
                self.logger.info(f"Brain scan resultaten opgeslagen: {scan_result['scan_name']}")
            else:
                self.logger.error(f"Opslaan brain scan resultaten mislukt: {response.status_code}")
                
        except Exception as e:
            self.logger.error(f"Fout bij opslaan brain scan resultaten: {e}")
            
    def get_next_safe_scan_time(self):
        """Bereken volgende veilige scan tijd"""
        now = datetime.now()
        if now.hour in self.safe_scan_hours:
            return now
        else:
            # Volgende veilige tijd is 22:00 vandaag of morgen
            if now.hour < 22:
                next_safe = now.replace(hour=22, minute=0, second=0, microsecond=0)
            else:
                next_safe = (now + timedelta(days=1)).replace(hour=22, minute=0, second=0, microsecond=0)
            return next_safe
            
    def generate_educational_report(self):
        """Genereer educatief specifiek rapport"""
        self.logger.info("Genereren educatief rapport")
        
        report = {
            'report_type': 'educational_scan',
            'timestamp': datetime.now().isoformat(),
            'component': 'brain-vps',
            'networks_scanned': self.educational_networks,
            'domains_scanned': self.school_domains,
            'safe_scan_hours': list(self.safe_scan_hours),
            'next_scan_time': self.get_next_safe_scan_time().isoformat(),
            'educational_guidelines': {
                'scan_only_outside_hours': True,
                'rate_limiting_enabled': True,
                'student_data_protection': True,
                'minimal_disruption': True
            }
        }
        
        # Stuur rapport naar API
        try:
            response = requests.post(
                f"{self.api_base_url}/vulnerabilities/educational-report",
                json=report,
                timeout=60
            )
            
            if response.status_code == 200:
                self.logger.info("Educatief rapport opgeslagen")
            else:
                self.logger.error(f"Educatief rapport opslaan mislukt: {response.status_code}")
                
        except Exception as e:
            self.logger.error(f"Fout bij opslaan educatief rapport: {e}")
            
        return report

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='IDPS Brain-VPS Nuclei Scanner')
    parser.add_argument('--scan-networks', action='store_true', help='Scan educatieve netwerken')
    parser.add_argument('--scan-domains', action='store_true', help='Scan school domeinen')
    parser.add_argument('--educational-report', action='store_true', help='Genereer educatief rapport')
    parser.add_argument('--all', action='store_true', help='Voer alle functies uit')
    
    args = parser.parse_args()
    
    scanner = BrainNucleiScanner()
    
    if args.all or args.educational_report:
        scanner.generate_educational_report()
    
    if args.all or args.scan_networks:
        scanner.scan_educational_networks()
        
    if args.all or args.scan_domains:
        scanner.scan_school_domains()

if __name__ == "__main__":
    main()
