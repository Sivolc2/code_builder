#!/usr/bin/env python3
import requests
import json
import os
import sys
from pathlib import Path

def get_openrouter_models(api_key):
    """Fetch available models from OpenRouter API."""
    url = "https://openrouter.ai/api/v1/models"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "HTTP-Referer": "https://github.com/feature_symphony_tool",  # Required by OpenRouter
    }
    
    try:
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error fetching models from OpenRouter: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    # Try to get API key from environment
    api_key = os.environ.get('OPENROUTER_API_KEY')
    
    # If not in environment, try to load from .env file
    if not api_key:
        env_path = Path(__file__).parent / '.env'
        if env_path.exists():
            print(f"Loading API key from {env_path}")
            with open(env_path, 'r') as f:
                for line in f:
                    if line.startswith('OPENROUTER_API_KEY='):
                        api_key = line.strip().split('=', 1)[1].strip('"\'')
                        break
    
    if not api_key:
        print("Error: OPENROUTER_API_KEY not found in environment or .env file", file=sys.stderr)
        sys.exit(1)
    
    print("Fetching models from OpenRouter API...")
    models_data = get_openrouter_models(api_key)
    
    # Save to file
    output_file = Path(__file__).parent / 'openrouter_models.json'
    with open(output_file, 'w') as f:
        json.dump(models_data, f, indent=2)
    
    print(f"Models saved to {output_file}")
    
    # Print summary
    if 'data' in models_data:
        models = models_data['data']
        print(f"\nFound {len(models)} models:")
        for model in models:
            print(f"- {model.get('id', 'Unknown ID')}")

if __name__ == "__main__":
    main() 