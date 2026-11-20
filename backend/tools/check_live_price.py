"""Read one public product listing; no accounts, orders or payments are created."""
from pathlib import Path
import argparse
import json
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.market import MarketClient

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('url', help='Exact HTTPS Arogga product link')
    args = parser.parse_args()
    result = MarketClient().quote(args.url)
    print(json.dumps(result, ensure_ascii=False, indent=2))
