import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Time "mo:base/Time";
import Option "mo:base/Option";
import Array "mo:base/Array";
import Int "mo:base/Int";

actor {

 
    type Volume = Nat;
    type VolumeWindow = {
        lastMove: Time.Time;
        total: Volume;
        window : [Volume] // 24 hours back from lastMove
    };

    private var pairVolume = HashMap.HashMap<Text, VolumeWindow>(1, Text.equal, Text.hash);
    private stable var pairsVolumeEntries: [(Text, VolumeWindow)] = [];

    // Update volume for a pair
    private func updateVolume(key: Text, t: Time.Time, volume_to_add: Volume) {
        
        let prev = Option.get(pairVolume.get(key), { lastMove=0; total=0; window = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]} : VolumeWindow);
        
        let hours_passed = (t - prev.lastMove)/(60*60*1000000000);
        
        if (hours_passed < 0) return; // There is an error, but we don't want to stop the swap from going through
        
        // shift window data based on hours passed
        let new_window : [var Nat] = Array.init(24, 0); // Creates new empty array with zeroes
        let start_index = Int.abs(hours_passed);

        // Only takes the data from the previous window which is in the current 24 hour window
        if (hours_passed <= 23) for (i in Iter.range(start_index,23)) { 
            new_window[i - start_index] := prev.window[i]; 
        };

        // add new volume to last hour
        new_window[23] := new_window[23] + volume_to_add;

        let new_vol : VolumeWindow = {
            lastMove = if (hours_passed > 0) t else prev.lastMove;
            total = prev.total + volume_to_add;
            window = Array.freeze(new_window);
        };

        pairVolume.put(key, new_vol);
    };

    // New canister function. Returns key, total volume in last 24 hours, and total volume since start of tracking.
    public query func getPairVolumes() : async ([(Text, Volume, Volume)]) {
        let t = Time.now();

        Iter.toArray(Iter.map<(Text, VolumeWindow), (Text, Volume, Volume)>(pairVolume.entries(), func (pair: (Text, VolumeWindow)) : (Text, Volume, Volume) {
            let (key, vol) = pair;
            let hours_passed = (t - vol.lastMove)/(60*60*1000000000);
            assert(hours_passed >= 0);
            var sum = 0;
            let start_index = Int.abs(hours_passed);
            if (hours_passed <= 23) for (i in Iter.range(start_index, 23)) {
                sum := sum + vol.window[i];
            };

            (key, sum, vol.total)
        }));
    };

    // Test function for development purposes only
    public func testUpdateVolume(items: [(key: Text, t: Time.Time, volume_to_add: Volume)]) : () {
        for (item in items.vals()) {
            updateVolume(item);
        };
    };

    

    system func preupgrade() {
        // Add to preupgrade
        pairsVolumeEntries := Iter.toArray(pairVolume.entries());
    };

    system func postupgrade() {
        // Add to postupgrade
        pairVolume := HashMap.fromIter<Text, VolumeWindow>(pairsVolumeEntries.vals(), 1, Text.equal, Text.hash);
    };
}
