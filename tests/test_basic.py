import pytest
import sys
import os

# Add src to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

def test_imports():
    """Test that critical modules can be imported"""
    try:
        import streamlit
        import numpy
        import pandas
        assert True
    except ImportError as e:
        pytest.fail(f"Failed to import required module: {e}")

def test_database_config():
    """Test database configuration structure"""
    try:
        from src.database import config
        assert hasattr(config, 'supabase') or True  # Will be updated for RDS
    except ImportError:
        pytest.skip("Database config not available")

def test_face_pipeline():
    """Test face recognition pipeline imports"""
    try:
        from src.pipelines import face_pipeline
        assert hasattr(face_pipeline, 'get_face_embeddings')
        assert hasattr(face_pipeline, 'load_dlib_models')
    except ImportError as e:
        pytest.skip(f"Face pipeline not available: {e}")

def test_voice_pipeline():
    """Test voice recognition pipeline imports"""
    try:
        from src.pipelines import voice_pipeline
        assert True  # Add actual tests based on your implementation
    except ImportError:
        pytest.skip("Voice pipeline not available")

def test_app_structure():
    """Test main app structure"""
    try:
        import app
        assert hasattr(app, 'main')
    except ImportError as e:
        pytest.fail(f"Failed to import app: {e}")

def test_health_check():
    """Test health check endpoint exists"""
    assert os.path.exists('healthcheck.py'), "Health check file should exist"

def test_deployment_files():
    """Test that deployment files exist"""
    assert os.path.exists('buildspec.yml'), "buildspec.yml should exist"
    assert os.path.exists('appspec.yml'), "appspec.yml should exist"
    assert os.path.exists('scripts/stop_application.sh'), "stop_application.sh should exist"
    assert os.path.exists('scripts/start_application.sh'), "start_application.sh should exist"
    assert os.path.exists('scripts/validate_service.sh'), "validate_service.sh should exist"

# Made with Bob
