import numpy as np
import os

def load_and_analyze_data(file_path):
    """Load and analyze numpy data file"""
    
    # Check if file exists
    if not os.path.exists(file_path):
        print(f"Error: File {file_path} not found!")
        return None
    
    try:
        # Load the data
        data = np.load(file_path)
        
        print(f"Data loaded from {file_path}:")
        print(f"Shape: {data.shape}")
        print(f"Data type: {data.dtype}")
        print(f"Memory usage: {data.nbytes / 1024:.2f} KB")
        
        # Statistical summary
        if data.size > 0:
            print(f"\nStatistical Summary:")
            print(f"Min value: {np.min(data):.4f}")
            print(f"Max value: {np.max(data):.4f}")
            print(f"Mean: {np.mean(data):.4f}")
            print(f"Std deviation: {np.std(data):.4f}")
            
            # Check for missing values (NaN)
            nan_count = np.isnan(data).sum()
            print(f"NaN values: {nan_count}")
            
            # Show first few rows if 2D
            if len(data.shape) == 2:
                print(f"\nFirst 5 rows:")
                print(data[:5])
                print(f"Number of features: {data.shape[1]}")
                print(f"Number of samples: {data.shape[0]}")
            else:
                print(f"\nFirst 10 values:")
                print(data[:10])
        
        return data
        
    except Exception as e:
        print(f"Error loading file: {e}")
        return None

if __name__ == "__main__":
    # Load training data
    file_path = './data/processed/X_train.npy'
    X_train = load_and_analyze_data(file_path)
    
    # Also check for other related files if they exist
    other_files = ['./data/y_train.npy', './data/X_test.npy', './data/y_test.npy']
    for file_path in other_files:
        if os.path.exists(file_path):
            print(f"\n{'='*50}")
            load_and_analyze_data(file_path)
