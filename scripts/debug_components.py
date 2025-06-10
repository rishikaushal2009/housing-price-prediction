import sys
import os

# Add the project root directory to sys.path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..'))
sys.path.append(PROJECT_ROOT)

from src.pipeline.housing_pipeline import train_model_op, predict_model_op
import inspect

print("=== Component Parameter Analysis ===")
print("\ntrain_model_op parameters:")
try:
    sig = inspect.signature(train_model_op.python_func)
    for param_name, param in sig.parameters.items():
        print(f"  - {param_name}: {param.annotation}")
except Exception as e:
    print(f"Error inspecting train_model_op: {e}")

print("\npredict_model_op parameters:")
try:
    sig = inspect.signature(predict_model_op.python_func)
    for param_name, param in sig.parameters.items():
        print(f"  - {param_name}: {param.annotation}")
except Exception as e:
    print(f"Error inspecting predict_model_op: {e}")