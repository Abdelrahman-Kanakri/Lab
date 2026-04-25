Drop binaries to distribute to lab devices in this folder.

Required for tomorrow:
  - meshagent.msi    (download from MeshCentral web UI: Lab group > Add Agent > Windows x64 MSI)

Optional:
  - SEB config files (.seb)
  - Any software installers you need to push

Anything placed here is served by serve_files.sh on http://<CONTROLLER_IP>:8080/
and is also pushable via Ansible's win_copy module.
