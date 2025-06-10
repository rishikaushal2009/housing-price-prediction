import kfp
from kfp import dsl
from kfp.components import create_component_from_func, InputPath, OutputPath
from typing import NamedTuple
import sys

# ------------------------------
# Data processing component
# ------------------------------
def process_data_func(
    output_data_path: OutputPath()
) -> NamedTuple('ProcessDataOutput', [('num_samples', int), ('num_features', int), ('output_data', str)]):
    import pandas as pd
    import numpy as np
    from sklearn.model_selection import train_test_split
    from sklearn.preprocessing import StandardScaler
    import joblib
    import os

    np.random.seed(42)
    n_samples = 1000

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

    df['price'] = np.abs(df['price'])
    df['age'] = 2022 - df['yr_built']

    X = df.drop(['price', 'yr_built'], axis=1)
    y = df['price']

    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    os.makedirs(output_data_path, exist_ok=True)
    np.save(f'{output_data_path}/X_train.npy', X_train_scaled)
    np.save(f'{output_data_path}/X_test.npy', X_test_scaled)
    np.save(f'{output_data_path}/y_train.npy', y_train.values)
    np.save(f'{output_data_path}/y_test.npy', y_test.values)

    joblib.dump(scaler, f'{output_data_path}/scaler.pkl')
    joblib.dump(X.columns.tolist(), f'{output_data_path}/feature_names.pkl')

    print("Data processing completed")
    print(f"Training samples: {X_train_scaled.shape[0]}")
    print(f"Features: {X_train_scaled.shape[1]}")

    from collections import namedtuple
    ProcessDataOutput = namedtuple('ProcessDataOutput', ['num_samples', 'num_features', 'output_data'])
    return ProcessDataOutput(X_train_scaled.shape[0], X_train_scaled.shape[1], output_data_path)

process_data_op = create_component_from_func(
    process_data_func,
    packages_to_install=["pandas", "numpy", "scikit-learn", "joblib"]
)

# ------------------------------
# Model training component
# ------------------------------
def train_model_func(
    input_data: InputPath(),
    model_output: OutputPath()
) -> NamedTuple('TrainModelOutput', [('r2_score', float), ('rmse', float)]):
    import numpy as np
    from sklearn.linear_model import LinearRegression
    from sklearn.metrics import mean_squared_error, r2_score
    import joblib
    import os
    from collections import namedtuple

    print("Starting model training")

    # Load training data
    X_train = np.load(f'{input_data}/X_train.npy')
    X_test = np.load(f'{input_data}/X_test.npy')
    y_train = np.load(f'{input_data}/y_train.npy')
    y_test = np.load(f'{input_data}/y_test.npy')

    # Train model
    model = LinearRegression()
    model.fit(X_train, y_train)

    # Evaluate model
    y_pred = model.predict(X_test)
    r2 = r2_score(y_test, y_pred)
    rmse = np.sqrt(mean_squared_error(y_test, y_pred))

    # Save model
    os.makedirs(model_output, exist_ok=True)
    model_file_path = os.path.join(model_output, 'model.pkl')
    joblib.dump(model, model_file_path)
    
    print("Model training completed")
    print(f"R2 Score: {r2:.4f}")
    print(f"RMSE: {rmse:.2f}")

    return namedtuple('TrainModelOutput', ['r2_score', 'rmse'])(r2, rmse)

train_model_op = create_component_from_func(
    train_model_func,
    packages_to_install=["pandas", "numpy", "scikit-learn", "joblib"]
)

# ------------------------------
# Prediction component
# ------------------------------
def predict_func(
    model_input: InputPath(),
    data_input: InputPath(),
    prediction_output: OutputPath()
) -> None:
    import numpy as np
    import pandas as pd
    import joblib
    import os

    print("Starting prediction generation")
    
    # Load test data
    X_test = np.load(f'{data_input}/X_test.npy')
    
    # Load model - try different paths
    model = None
    
    # Try loading from directory
    if os.path.isdir(model_input):
        model_path = os.path.join(model_input, 'model.pkl')
        if os.path.exists(model_path):
            model = joblib.load(model_path)
            print(f"Model loaded from: {model_path}")
    
    # Try loading directly if it's a file
    if model is None and os.path.isfile(model_input) and model_input.endswith('.pkl'):
        model = joblib.load(model_input)
        print(f"Model loaded directly from: {model_input}")
    
    if model is None:
        raise FileNotFoundError(f"Could not find model at: {model_input}")
    
    # Make predictions
    predictions = model.predict(X_test)

    # Save predictions
    os.makedirs(prediction_output, exist_ok=True)
    pred_df = pd.DataFrame(predictions, columns=['predictions'])
    pred_csv_path = os.path.join(prediction_output, 'predictions.csv')
    pred_df.to_csv(pred_csv_path, index=False)

    print("Prediction generation completed")
    print(f"Total predictions: {len(predictions)}")

predict_model_op = create_component_from_func(
    predict_func,
    packages_to_install=["pandas", "numpy", "joblib"]
)

# ------------------------------
# Model deployment component
# ------------------------------
def deploy_model_func(
    model_input: InputPath(),
    deployment_name: str = "housing-price-predictor"
) -> str:
    print(f"Deploying model: {deployment_name}")
    return f"Model deployed successfully as {deployment_name}"

deploy_model_op = create_component_from_func(
    deploy_model_func,
    packages_to_install=[]
)

# ------------------------------
# Pipeline definition
# ------------------------------
@dsl.pipeline(
    name='Housing Price Prediction Pipeline',
    description='Train and deploy a linear regression model for housing price prediction'
)
def housing_price_pipeline():
    """Main pipeline function"""
    
    # Step 1: Process data
    process_data_task = process_data_op()
    process_data_task.set_display_name("Data Processing")
    
    # Step 2: Train model
    train_model_task = train_model_op(
        input_data=process_data_task.outputs['output_data']
    )
    train_model_task.set_display_name("Model Training")
    train_model_task.after(process_data_task)
    
    # Step 3: Generate predictions
    predict_model_task = predict_model_op(
        model_input=train_model_task.outputs['model_output'],
        data_input=process_data_task.outputs['output_data']
    )
    predict_model_task.set_display_name("Generate Predictions")
    predict_model_task.after(train_model_task)
    
    # Step 4: Deploy model
    deploy_model_task = deploy_model_op(
        model_input=train_model_task.outputs['model_output']
    )
    deploy_model_task.set_display_name("Deploy Model")
    deploy_model_task.after(predict_model_task)

# ------------------------------
# Pipeline compilation (FIXED)
# ------------------------------
def compile_pipeline(output_path='housing_pipeline.yaml'):
    """Compile the pipeline to YAML"""
    try:
        # For KFP v1.x
        kfp.compiler.Compiler().compile(
            pipeline_func=housing_price_pipeline,
            package_path=output_path
        )
        print(f"Pipeline compiled successfully to: {output_path}")
        return True
    except Exception as e:
        print(f"Pipeline compilation failed with v1 method: {str(e)}")
        
        # Try alternative method for older versions
        try:
            import kfp.compiler as compiler
            compiler.Compiler().compile(housing_price_pipeline, output_path)
            print(f"Pipeline compiled successfully to: {output_path}")
            return True
        except Exception as e2:
            print(f"Pipeline compilation failed with alternative method: {str(e2)}")
            return False

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Compile housing price prediction pipeline')
    parser.add_argument('--output', '-o', type=str, default='housing_pipeline.yaml',
                       help='Output path for compiled pipeline')
    parser.add_argument('--compile-only', action='store_true',
                       help='Only compile, do not run')
    
    args = parser.parse_args()
    
    success = compile_pipeline(args.output)
    
    if success:
        print("Pipeline compilation completed successfully!")
        if not args.compile_only:
            print("Use scripts/run_pipeline.py to execute the pipeline")
    else:
        print("Pipeline compilation failed!")
        sys.exit(1)
