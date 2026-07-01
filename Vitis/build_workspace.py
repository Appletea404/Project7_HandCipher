import vitis
import sys

try:
    client = vitis.create_client()
    client.set_workspace(path="Vitis")

    print("--- Building platform_HandCipher ---")
    platform = client.get_component(name="platform_HandCipher")
    platform.build()

    print("--- Building HandCipher application ---")
    comp = client.get_component(name="HandCipher")
    comp.build()

    print("--- Build Finished Successfully ---")
    vitis.dispose()
except Exception as e:
    print(f"Error occurred: {e}")
    sys.exit(1)
