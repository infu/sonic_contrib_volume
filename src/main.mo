import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Time "mo:base/Time";
import Option "mo:base/Option";
import Array "mo:base/Array";
import Int "mo:base/Int";
import Map "mo:map/Map";
import { thash } "mo:map/Map";
import Cap "./services/cap";
import Nat32 "mo:base/Nat32";
import Timer "mo:base/Timer";
import Nat "mo:base/Nat";
import Int64 "mo:base/Int64";
import Error "mo:base/Error";
import Swb "mo:swb";
import Debug "mo:base/Debug";
import Nat64 "mo:base/Nat64";

actor {
    type Volume = Nat;
    type VolumeWindow = {
        lastMove : Time.Time;
        total : Volume;
        window : [Volume] // 24 hours back from lastMove
    };

    type ErrorLine = (Time.Time, Text, Error.ErrorCode, Text);

    let errorsLog = Swb.SlidingWindowBuffer<ErrorLine>();

    let history = actor ("vemis-oyaaa-aaaah-adpkq-cai") : Cap.Self;

    stable var digested : Nat = 0;
    stable var curPage : Nat = 14175;
    stable var nextTxIdx : Nat = 0;
    stable var historyRequests : Nat = 0;

    // public shared func test(page : Nat) : async Cap.GetTransactionsResponseBorrowed {
    //     await history.get_transactions({
    //         page = ?Nat32.fromNat(page);
    //         witness = false;
    //     });
    // };

    private func digest(tx : Cap.Event) {
        if (tx.operation != "swap") return;
        digested := digested + 1;
        let ? #Text(pair_id) = find_val("pairId", tx.details) else Debug.trap("pairId not found");
        // let ? #Text(amountInText) = find_val("amountIn", tx.details) else Debug.trap("amountIn not found " # debug_show (tx));
        // let ?volume = Nat.fromText(amountInText) else Debug.trap("volume not a number");
        let ?weirdVolume = find_val("amountIn", tx.details) else Debug.trap("amountIn not found " # debug_show (tx));
        let volume = switch (weirdVolume) {
            case (#Text(amountInText)) {
                let ?tmp = Nat.fromText(amountInText) else Debug.trap("volume not a number");
                tmp;
            };
            case (#U64(volU64)) {
                Nat64.toNat(volU64);
            };
            case (_) Debug.trap("amountIn unexpected type " # debug_show (tx));
        };
        let time = Int64.toInt(Int64.fromNat64(tx.time));
        updateVolume(pair_id, time, volume);
    };

    private func find_val(key : Text, values : [(Text, Cap.DetailValue)]) : ?Cap.DetailValue {
        let ?f = Array.find<(Text, Cap.DetailValue)>(values, func((k : Text, d : Cap.DetailValue)) = k == key) else return null;
        ?f.1;
    };

    private func check_for_new_tx_log() : async () {
        try {
            await check_for_new_tx();
        } catch e {
            logErr("history request ", e);
        };
    };

    // Adds an error to the error log
    private func logErr(desc : Text, e : Error.Error) : () {
        ignore errorsLog.add((Time.now(), desc, Error.code(e), Error.message(e)));
        if (errorsLog.len() > 500) {
            errorsLog.delete(1);
        };
    };

    // Displays the error log entries
    public query func log_show() : async [?ErrorLine] {
        let start = errorsLog.start();
        let end = errorsLog.end();
        Array.tabulate(
            errorsLog.len(),
            func(i : Nat) : ?ErrorLine {
                errorsLog.getOpt(start + i);
            },
        );
    };

    private func check_for_new_tx() : async () {
        historyRequests += 1;
        let rez = await history.get_transactions({
            page = ?Nat32.fromNat(curPage);
            witness = false;
        });
        let len = rez.data.size();
        if (len != 0) {
            var i = nextTxIdx;
            label scan loop {
                if (i >= len) break scan;
                digest(rez.data[i]);
                i += 1;
            };
            nextTxIdx := len;
        };

        if (len >= 64) {
            curPage += 1;
            nextTxIdx := 0;
            ignore Timer.setTimer(#seconds 0, check_for_new_tx_log);
        } else {
            ignore Timer.setTimer(#seconds 5, check_for_new_tx_log);
        };
    };

    private var pairVolume = Map.new<Text, VolumeWindow>();

    // Update volume for a pair
    private func updateVolume(key : Text, t : Time.Time, volume_to_add : Volume) {

        let prev = Option.get(Map.get(pairVolume, thash, key), { lastMove = 0; total = 0; window = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] } : VolumeWindow);

        let hours_passed = (t - prev.lastMove) / (60 * 60 * 1000);

        if (hours_passed < 0) return; // There is an error, but we don't want to stop the swap from going through

        // shift window data based on hours passed
        let new_window : [var Nat] = Array.init(24, 0); // Creates new empty array with zeroes
        let start_index = Int.abs(hours_passed);

        // Only takes the data from the previous window which is in the current 24 hour window
        if (hours_passed <= 23) for (i in Iter.range(start_index, 23)) {
            new_window[i - start_index] := prev.window[i];
        };

        // add new volume to last hour
        new_window[23] := new_window[23] + volume_to_add;

        let new_vol : VolumeWindow = {
            lastMove = if (hours_passed > 0) t else prev.lastMove;
            total = prev.total + volume_to_add;
            window = Array.freeze(new_window);
        };

        Map.set(pairVolume, thash, key, new_vol);
    };

    // New canister function. Returns key, total volume in last 24 hours, and total volume since start of tracking.
    public query func getPairVolumes() : async ([(Text, Volume, Volume)]) {
        let t = Time.now();

        Iter.toArray(
            Iter.map<(Text, VolumeWindow), (Text, Volume, Volume)>(
                Map.entries(pairVolume),
                func(pair : (Text, VolumeWindow)) : (Text, Volume, Volume) {
                    let (key, vol) = pair;
                    let hours_passed = (t - vol.lastMove) / (60 * 60 * 1000);
                    assert (hours_passed >= 0);
                    var sum = 0;
                    let start_index = Int.abs(hours_passed);
                    if (hours_passed <= 23) for (i in Iter.range(start_index, 23)) {
                        sum := sum + vol.window[i];
                    };

                    (key, sum, vol.total);
                },
            )
        );
    };

    type Stats = {
        digested : Nat;
        curPage : Nat;
        nextTxIdx : Nat;
        historyRequests : Nat;
    };

    public query func stats() : async Stats {
        {
            digested;
            curPage;
            nextTxIdx;
            historyRequests;
        };
    };

    // Test function for development purposes only
    // public func testUpdateVolume(items : [(key : Text, t : Time.Time, volume_to_add : Volume)]) : () {
    //     for (item in items.vals()) {
    //         updateVolume(item);
    //     };
    // };

    ignore Timer.setTimer(#seconds 1, check_for_new_tx_log);

};
