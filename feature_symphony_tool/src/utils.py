# feature_symphony_tool/src/utils.py
import yaml
import os
import json
from pathlib import Path
import google.generativeai as genai
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

def get_gemini_api_key(config: dict) -> str:
    """Retrieves Gemini API key from config or environment variable."""
    api_key = config.get('gemini_api_key')
    if not api_key:
        api_key = os.environ.get('GEMINI_API_KEY')
    
    if not api_key:
        raise ConfigError("Gemini API key not found. Set 'gemini_api_key' in config or GEMINI_API_KEY environment variable.")
    return api_key

def call_gemini_api(prompt_text: str, api_key: str, model_name: str) -> str:
    """
    Calls the Gemini API with the given prompt and returns the text response.
    """
    print(f"\nCalling Gemini API with model: {model_name}...")
    # print(f"Prompt (first 100 chars): {prompt_text[:100]}...")

    genai.configure(api_key=api_key)
    
    generation_config = {
        "temperature": 0.7,  # Adjust as needed for creativity vs. precision
        "top_p": 1,
        "top_k": 1,
        "max_output_tokens": 8192,  # Max for gemini-1.5-pro
    }
    
    safety_settings = [
        {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
        {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
        {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
        {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
    ]

    try:
        model = genai.GenerativeModel(model_name=model_name,
                                      generation_config=generation_config,
                                      safety_settings=safety_settings)
        
        response = model.generate_content(prompt_text)
        
        if response.candidates and response.candidates[0].content.parts:
            generated_text = "".join(part.text for part in response.candidates[0].content.parts)
            print("Gemini API call successful.")
            return generated_text
        else:
            # Check for blocked content due to safety settings or other reasons
            if response.prompt_feedback and response.prompt_feedback.block_reason:
                raise Exception(f"Gemini API call blocked. Reason: {response.prompt_feedback.block_reason_message or response.prompt_feedback.block_reason}")
            raise Exception("Gemini API call failed: No content in response or unexpected response structure.")

    except Exception as e:
        print(f"Error calling Gemini API: {e}")
        raise  # Re-raise the exception to be caught by the orchestrator

def generate_slug(text: str) -> str:
    """Generates a URL-friendly slug from text."""
    return slugify(text, max_length=50, word_boundary=True, separator="_") 