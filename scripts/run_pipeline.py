import kfp
import argparse
import sys
import os
import time

# Add the project root directory to sys.path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..'))
sys.path.append(PROJECT_ROOT)

def run_pipeline(host, experiment_name="housing-price-experiment"):
    """Run the housing price prediction pipeline"""
    
    run_result = None
    
    try:
        # Create client with more detailed connection info
        print(f"Connecting to Kubeflow Pipelines at: {host}")
        client = kfp.Client(host=host)
        print("Successfully connected to Kubeflow Pipelines")
        
        # Test connection more thoroughly
        try:
            experiments = client.list_experiments()
            print(f"Connection verified - found {experiments.total_size} experiments")
            
            # List existing experiments
            if experiments.experiments:
                print("Existing experiments:")
                for exp in experiments.experiments:
                    print(f"  - {exp.name} (ID: {exp.id})")
            
        except Exception as e:
            print(f"Warning: Could not list experiments: {e}")
            print("This might indicate connection issues with Kubeflow Pipelines")
        
        # Create or get experiment
        experiment = None
        try:
            experiment = client.get_experiment(experiment_name=experiment_name)
            print(f"Using existing experiment: {experiment_name} (ID: {experiment.id})")
        except Exception:
            try:
                experiment = client.create_experiment(name=experiment_name)
                print(f"Created new experiment: {experiment_name} (ID: {experiment.id})")
            except Exception as e:
                print(f"Failed to create experiment: {e}")
                return None
        
        if not experiment:
            print("Error: Could not create or get experiment")
            return None
        
        # Import and submit pipeline
        print("Importing pipeline...")
        from src.pipeline.housing_pipeline import housing_price_pipeline
        print("Pipeline imported successfully")
        
        # Try to compile pipeline first to check for issues
        print("Testing pipeline compilation...")
        try:
            import tempfile
            with tempfile.NamedTemporaryFile(suffix='.yaml', delete=False) as tmp_file:
                kfp.compiler.Compiler().compile(housing_price_pipeline, tmp_file.name)
                print("Pipeline compilation test successful")
                os.unlink(tmp_file.name)  # Clean up temp file
        except Exception as e:
            print(f"Pipeline compilation test failed: {e}")
            return None
        
        print("Submitting pipeline run...")
        run_name = f"housing-price-run-{int(time.time())}"  # Create unique run name
        
        run_result = client.create_run_from_pipeline_func(
            housing_price_pipeline,
            arguments={},
            experiment_name=experiment_name,
            run_name=run_name
        )
        
        print("Pipeline submitted successfully!")
        print(f"Run ID: {run_result.run_id}")
        print(f"Run Name: {run_name}")  # Use the run_name we created
        print(f"Experiment ID: {experiment.id}")
        print(f"Run URL: {host}/#/runs/details/{run_result.run_id}")
        
        # Wait a moment and check run status
        print("\nChecking run status...")
        time.sleep(3)
        
        try:
            run_detail = client.get_run(run_result.run_id)
            print(f"Run Status: {run_detail.run.status}")
            
            if hasattr(run_detail.run, 'status') and run_detail.run.status:
                print(f"Run Phase: {run_detail.run.status}")
            
            # Check if there are any error messages
            if hasattr(run_detail.run, 'error') and run_detail.run.error:
                print(f"Run Error: {run_detail.run.error}")
                
        except Exception as e:
            print(f"Could not retrieve run status: {e}")
        
        return run_result
        
    except Exception as e:
        print(f"Pipeline submission failed: {str(e)}")
        print(f"Error type: {type(e).__name__}")
        
        # More detailed error information
        import traceback
        print("\nFull error traceback:")
        traceback.print_exc()
        
        print("\nTroubleshooting:")
        print("1. Check if Kubeflow Pipelines server is running")
        print("2. Verify the host URL is correct")
        print("3. Check if you can access the Kubeflow UI in browser")
        print("4. Try compiling the pipeline first:")
        print("   python src/pipeline/housing_pipeline.py")
        print("5. Check Kubeflow Pipelines logs for errors")
        
        return None

def test_connection(host):
    """Test connection to Kubeflow Pipelines"""
    print(f"Testing connection to: {host}")
    
    try:
        client = kfp.Client(host=host)
        
        # Test basic operations
        experiments = client.list_experiments()
        print(f"Connection successful - found {experiments.total_size} experiments")
        
        # Test pipeline operations
        runs = client.list_runs()
        print(f"Can list runs - found {runs.total_size} runs")
        
        return True
        
    except Exception as e:
        print(f"Connection failed: {e}")
        return False

def get_run_details(client, run_id):
    """Get detailed information about a run"""
    try:
        run_detail = client.get_run(run_id)
        
        print(f"\n=== Run Details ===")
        print(f"Run ID: {run_id}")
        
        if hasattr(run_detail, 'run') and run_detail.run:
            run = run_detail.run
            
            # Basic run information
            if hasattr(run, 'name'):
                print(f"Run Name: {run.name}")
            if hasattr(run, 'status'):
                print(f"Status: {run.status}")
            if hasattr(run, 'created_at'):
                print(f"Created: {run.created_at}")
            if hasattr(run, 'finished_at') and run.finished_at:
                print(f"Finished: {run.finished_at}")
            
            # Error information if available
            if hasattr(run, 'error') and run.error:
                print(f"Error: {run.error}")
        
        return run_detail
        
    except Exception as e:
        print(f"Could not get run details: {e}")
        return None

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Run housing price prediction pipeline')
    parser.add_argument('--host', type=str, required=True, 
                       help='Kubeflow Pipelines host URL')
    parser.add_argument('--experiment-name', type=str, default='housing-price-experiment',
                       help='Name of the experiment')
    parser.add_argument('--test-connection', action='store_true',
                       help='Only test connection, do not run pipeline')
    parser.add_argument('--get-run-details', type=str,
                       help='Get details for a specific run ID')
    
    args = parser.parse_args()
    
    # Ensure host has proper protocol
    host = args.host
    if not host.startswith(('http://', 'https://')):
        host = f'http://{host}'
    
    print(f"Starting pipeline execution...")
    print(f"Host: {host}")
    print(f"Experiment: {args.experiment_name}")
    
    # Test connection first if requested
    if args.test_connection:
        if test_connection(host):
            print("Connection test passed!")
            sys.exit(0)
        else:
            print("Connection test failed!")
            sys.exit(1)
    
    # Get run details if requested
    if args.get_run_details:
        try:
            client = kfp.Client(host=host)
            get_run_details(client, args.get_run_details)
            sys.exit(0)
        except Exception as e:
            print(f"Failed to get run details: {e}")
            sys.exit(1)
    
    result = run_pipeline(host, args.experiment_name)
    
    if result:
        print("\n=== Pipeline Execution Started ===")
        print("Monitor progress in the Kubeflow UI")
        print(f"Direct link: {host}/#/runs/details/{result.run_id}")
        sys.exit(0)
    else:
        print("\n=== Pipeline Execution Failed ===")
        sys.exit(1)