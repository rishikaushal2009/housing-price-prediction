import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
import joblib
import argparse
import os
from pathlib import Path

def load_and_process_data(data_path, output_path):
    """Load and preprocess housing data"""
    
    try:
        # Convert paths to Path objects for better handling
        output_path = Path(output_path)
        
        # For demo purposes, we'll create synthetic data
        # In real scenario, you'd load from your data source
        np.random.seed(42)
        n_samples = 1000
        
        print("Generating synthetic housing data...")
        
        # Generate synthetic housing data
        data = {
            'bedrooms': np.random.randint(1, 6, n_samples),
            'bathrooms': np.random.randint(1, 4, n_samples),
            'sqft_living': np.random.randint(500, 5000, n_samples),
            'sqft_lot': np.random.randint(1000, 20000, n_samples),
            'floors': np.random.choice([1, 1.5, 2, 2.5, 3], n_samples),
            'waterfront': np.random.choice([0, 1], n_samples, p=[0.9, 0.1]),
            'condition': np.random.randint(1, 6, n_samples),
            'grade': np.random.randint(3, 13, n_samples),
            'yr_built': np.random.randint(1900, 2022, n_samples),
        }
        
        df = pd.DataFrame(data)
        
        # Create target variable (price) based on features
        df['price'] = (
            df['bedrooms'] * 20000 +
            df['bathrooms'] * 15000 +
            df['sqft_living'] * 150 +
            df['sqft_lot'] * 5 +
            df['floors'] * 10000 +
            df['waterfront'] * 100000 +
            df['condition'] * 5000 +
            df['grade'] * 8000 +
            (2022 - df['yr_built']) * -500 +
            np.random.normal(0, 50000, n_samples)
        )
        
        # Ensure positive prices
        df['price'] = np.abs(df['price'])
        
        print("Performing feature engineering...")
        
        # Feature engineering
        df['age'] = 2022 - df['yr_built']
        df['price_per_sqft'] = df['price'] / df['sqft_living']
        
        # Split features and target
        X = df.drop(['price', 'yr_built'], axis=1)
        y = df['price']
        
        print("Splitting data into train and test sets...")
        
        # Train-test split
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42
        )
        
        print("Scaling features...")
        
        # Scale features
        scaler = StandardScaler()
        X_train_scaled = scaler.fit_transform(X_train)
        X_test_scaled = scaler.transform(X_test)
        
        # Create output directory
        try:
            output_path.mkdir(parents=True, exist_ok=True)
            print(f"Created output directory: {output_path}")
        except PermissionError:
            print(f"Permission denied. Cannot create directory: {output_path}")
            print("Using current directory instead...")
            output_path = Path("./processed_data")
            output_path.mkdir(parents=True, exist_ok=True)
        
        print("Saving processed data...")
        
        # Save processed data
        np.save(output_path / 'X_train.npy', X_train_scaled)
        np.save(output_path / 'X_test.npy', X_test_scaled)
        np.save(output_path / 'y_train.npy', y_train.values)
        np.save(output_path / 'y_test.npy', y_test.values)
        
        # Save original unscaled data for reference
        X_train.to_csv(output_path / 'X_train_original.csv', index=False)
        X_test.to_csv(output_path / 'X_test_original.csv', index=False)
        y_train.to_csv(output_path / 'y_train.csv', index=False)
        y_test.to_csv(output_path / 'y_test.csv', index=False)
        
        # Save scaler and feature names
        joblib.dump(scaler, output_path / 'scaler.pkl')
        joblib.dump(X.columns.tolist(), output_path / 'feature_names.pkl')
        
        # Save data statistics
        stats = {
            'n_samples': n_samples,
            'n_features': X.shape[1],
            'train_size': X_train_scaled.shape[0],
            'test_size': X_test_scaled.shape[0],
            'feature_names': X.columns.tolist(),
            'target_stats': {
                'mean': float(y.mean()),
                'std': float(y.std()),
                'min': float(y.min()),
                'max': float(y.max())
            }
        }
        
        import json
        with open(output_path / 'data_stats.json', 'w') as f:
            json.dump(stats, f, indent=2)
        
        print(f"\n✅ Data processed and saved to {output_path}")
        print(f"📊 Training samples: {X_train_scaled.shape[0]}")
        print(f"📊 Test samples: {X_test_scaled.shape[0]}")
        print(f"📊 Features: {X_train_scaled.shape[1]}")
        print(f"📊 Feature names: {X.columns.tolist()}")
        print(f"💰 Price range: ${y.min():,.0f} - ${y.max():,.0f}")
        print(f"💰 Average price: ${y.mean():,.0f}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error processing data: {str(e)}")
        return False

def main():
    """Main function to handle command line arguments"""
    parser = argparse.ArgumentParser(description='Process housing data for ML pipeline')
    parser.add_argument('--data-path', type=str, default='./data/raw', 
                       help='Path to raw data directory')
    parser.add_argument('--output-path', type=str, default='./data/processed',
                       help='Path to save processed data')
    
    args = parser.parse_args()
    
    print("🏠 Housing Price Prediction - Data Processor")
    print("=" * 50)
    print(f"Data path: {args.data_path}")
    print(f"Output path: {args.output_path}")
    print("=" * 50)
    
    success = load_and_process_data(args.data_path, args.output_path)
    
    if success:
        print("\n✅ Data processing completed successfully!")
    else:
        print("\n❌ Data processing failed!")
        exit(1)

if __name__ == "__main__":
    main()