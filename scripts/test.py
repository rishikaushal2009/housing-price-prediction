import kfp
import argparse

def check_pipeline_results(host, run_id):
    client = kfp.Client(host=host)
    
    try:
        # Get run details
        run_detail = client.get_run(run_id)
        print(f"Pipeline Status: {run_detail.run.status}")
        print(f"Pipeline Name: {run_detail.run.name}")
        print(f"Created At: {run_detail.run.created_at}")
        
        # Get run results
        if run_detail.run.status == "Succeeded":
            print("\n=== Pipeline Completed Successfully ===")
            
            # List artifacts
            try:
                artifacts = client.runs.list_artifacts(run_id=run_id)
                print(f"\nArtifacts found: {len(artifacts.artifacts) if artifacts.artifacts else 0}")
                
                if artifacts.artifacts:
                    for artifact in artifacts.artifacts:
                        print(f"- {artifact.name}: {artifact.uri}")
            except Exception as e:
                print(f"Could not retrieve artifacts: {e}")
                
        elif run_detail.run.status == "Failed":
            print("\n=== Pipeline Failed ===")
            print("Check the Kubeflow UI for error details")
            
        elif run_detail.run.status == "Running":
            print("\n=== Pipeline Still Running ===")
            print("Wait for completion to see results")
            
    except Exception as e:
        print(f"Error checking pipeline: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='http://localhost:8080')
    parser.add_argument('--run-id', required=True)
    args = parser.parse_args()
    
    check_pipeline_results(args.host, args.run_id)

