import os
import subprocess
import sys
import shutil

def deploy(hf_username, hf_token=None):
    backend_dir = os.path.dirname(os.path.abspath(__file__))
    temp_dir = os.path.join(backend_dir, ".hf_deploy_temp")
    
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir, ignore_errors=True)
    os.makedirs(temp_dir, exist_ok=True)
    
    files_to_copy = [
        "Dockerfile", "requirements.txt", "app.py", "database.py",
        "email_service.py", "push_service.py", "README.md", ".env"
    ]
    
    for f in files_to_copy:
        src = os.path.join(backend_dir, f)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(temp_dir, f))
            
    # Copy uploads folder structure if exists
    os.makedirs(os.path.join(temp_dir, "uploads"), exist_ok=True)
    
    repo_url = f"https://huggingface.co/spaces/{hf_username}/gebtalk-backend"
    if hf_token:
        repo_url = f"https://{hf_username}:{hf_token}@huggingface.co/spaces/{hf_username}/gebtalk-backend"
        
    print(f"Deploying to Hugging Face Space: https://huggingface.co/spaces/{hf_username}/gebtalk-backend")
    
    cmds = [
        ["git", "init"],
        ["git", "config", "user.name", hf_username],
        ["git", "config", "user.email", f"{hf_username}@users.noreply.huggingface.co"],
        ["git", "checkout", "-b", "main"],
        ["git", "add", "."],
        ["git", "commit", "-m", "Deploy GEBTALK global voice calling backend"],
        ["git", "remote", "add", "origin", repo_url],
        ["git", "push", "--force", "origin", "main"]
    ]
    
    for cmd in cmds:
        res = subprocess.run(cmd, cwd=temp_dir, capture_output=True, text=True)
        if res.returncode != 0 and "push" in cmd:
            print(f"Error during push: {res.stderr}")
            return False
            
    print(f"\n[SUCCESS] Successfully pushed backend to Hugging Face Space!")
    print(f"Permanent Live Server API URL: https://{hf_username.lower()}-gebtalk-backend.hf.space/api")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python deploy_to_hf.py <HF_USERNAME> [HF_TOKEN]")
        sys.exit(1)
    user = sys.argv[1]
    tok = sys.argv[2] if len(sys.argv) > 2 else None
    deploy(user, tok)
