# feature_symphony_tool/src/utils.py
import yaml
import os
import requests # Added for API calls
from pathlib import Path
from slugify import slugify  # from python-slugify import slugify

class ConfigError(Exception):
    pass

def load_config(config_file_path: Path) -> dict:
    """Loads configuration from a YAML file."""
    try:
        with open(config_file_path, 'r') as f:
            config_data = yaml.safe_load(f)
        if not config_data:
            raise ConfigError(f"Config file is empty or invalid: {config_file_path}")
        return config_data
    except FileNotFoundError:
        raise ConfigError(f"Configuration file not found: {config_file_path}")
    except yaml.YAMLError as e:
        raise ConfigError(f"Error parsing YAML configuration file: {config_file_path} - {e}")

def get_openrouter_api_key() -> str:
    """Retrieves OpenRouter API key from environment variable."""
    # OpenRouter key MUST be set in environment for security
    api_key = os.environ.get('OPENROUTER_API_KEY')
    
    if not api_key:
        raise ConfigError("OpenRouter API key not found. Set the OPENROUTER_API_KEY environment variable.")
    return api_key

def call_openrouter_api(prompt_text: str, api_key: str, model_name: str, feature_name: str = None) -> str:
    """
    Calls the OpenRouter API with the given prompt and returns the text response.
    """
    feature_info = f" for '{feature_name}'" if feature_name else ""
    print(f"Calling OpenRouter API{feature_info} with model: {model_name}")

    OPENROUTER_API_BASE = "https://openrouter.ai/api/v1"
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
        # Optional: "X-Title": "Feature Symphony Tool" # Helps OpenRouter track usage
    }
    
    try:
        response = requests.post(
            f"{OPENROUTER_API_BASE}/chat/completions",
            headers=headers,
            json={
                "model": model_name,
                "messages": [{"role": "user", "content": prompt_text}],
                "temperature": 0.7,
                "max_tokens": 8000 # Use slightly less than context window max just in case
            }
        )
        response.raise_for_status() # Raise an exception for bad status codes (4xx or 5xx)
        
        response_data = response.json()
        
        if response_data and 'choices' in response_data and response_data['choices']:
            generated_text = response_data['choices'][0]['message']['content']
            print(f"OpenRouter API call successful{feature_info}.")
            return generated_text
        else:
            # Print full response for debugging if no choices
            print("OpenRouter API Response (Problem):", response_data)
            raise Exception("OpenRouter API call failed: Unexpected response structure.")

    except Exception as e:
        print(f"Error calling OpenRouter API{feature_info}: {e}")
        raise

def generate_slug(text: str) -> str:
    """Generates a URL-friendly slug from the given text."""
    return slugify(text) 