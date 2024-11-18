import random, time
from pythonosc.udp_client import SimpleUDPClient

def main():
    client = SimpleUDPClient("127.0.0.1", 57120)  # REVISAR PUERTO DE SC PREVIAMENTE
    print("Starting OSC transmission...")
    print("Press Ctrl+C to stop")
    
    try:
        while True:
            osc1 = random.uniform(-1, 1)
            osc2 = random.uniform(-1, 1)
            # Enviamos los valores individuales, no como lista
            client.send_message("/inputs", [osc1, osc2])  
            print(f"Sending OSC: {osc1:.2f}, {osc2:.2f}")
            time.sleep(0.1)
    except KeyboardInterrupt:
        print("\nStopping OSC transmission...")
        time.sleep(0.5)

if __name__ == "__main__":
    main()