import numpy as np
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error, r2_score, mean_absolute_error
import joblib
import argparse
import os
import json

def train_model(data_path, model_path, metrics_path):
    """Train linear regression model"""
    
    # Load processed data
    X_train = np.load(f'{data_path}/X_train.npy')
    X_test = np.load(f'{data_path}/X_test.npy')
    y_train = np.load(f'{data_path}/y_train.npy')
    y_test = np.load(f'{data_path}/y_test.npy')
    
    # Train model
    model = LinearRegression()
    model.fit(X_train, y_train)
    
    # Make predictions
    y_train_pred = model.predict(X_train)
    y_test_pred = model.predict(X_test)
    
    # Calculate metrics
    train_metrics = {
        'mse': float(mean_squared_error(y_train, y_train_pred)),
        'rmse': float(np.sqrt(mean_squared_error(y_train, y_train_pred))),
        'mae': float(mean_absolute_error(y_train, y_train_pred)),
        'r2': float(r2_score(y_train, y_train_pred))
    }
    
    test_metrics = {
        'mse': float(mean_squared_error(y_test, y_test_pred)),
        'rmse': float(np.sqrt(mean_squared_error(y_test, y_test_pred))),
        'mae': float(mean_absolute_error(y_test, y_test_pred)),
        'r2': float(r2_score(y_test, y_test_pred))
    }
    
    metrics = {
        'train': train_metrics,
        'test': test_metrics
    }
    
    # Save model
    os.makedirs(model_path, exist_ok=True)
    joblib.dump(model, f'{model_path}/model.pkl')
    
    # Save metrics
    os.makedirs(metrics_path, exist_ok=True)
    with open(f'{metrics_path}/metrics.json', 'w') as f:
        json.dump(metrics, f, indent=2)
    
    print("Model training completed!")
    print(f"Test R2 Score: {test_metrics['r2']:.4f}")
    print(f"Test RMSE: {test_metrics['rmse']:.2f}")
    print(f"Test MAE: {test_metrics['mae']:.2f}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--data-path', type=str, default='/data/processed')
    parser.add_argument('--model-path', type=str, default='/model')
    parser.add_argument('--metrics-path', type=str, default='/metrics')
    
    args = parser.parse_args()
    train_model(args.data_path, args.model_path, args.metrics_path)