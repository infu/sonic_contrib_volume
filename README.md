Volume Tracking System made for Sonic DAO by ICPCoins.
It will allow Sonic DAO to track the volume of different pairs over a rolling 24-hour window.
Why is it needed? Sonic DAO currently relies on off-chain db for volume and charts.
ICPCoins and other contracts on the IC can't access that API on-chain.


Data Structures:
    - VolumeWindow: A record type that stores the last trade time (lastMove) and an array (window) representing volume data for 24 hours,
        hour by hour.

Storing Volume Data:
    - pairVolume: A HashMap that associates each trading pair (identified by Text) with its corresponding VolumeWindow.
    - pairsVolumeEntries: A stable variable to persist data across upgrades. It's a list of tuples, each containing a trading 
    - pair and its VolumeWindow.

Updating Volume Data (updateVolume function):
    - For a given trading pair, it calculates the time elapsed since the last trade.
    - Based on the elapsed time, it shifts the volume data in the window. Older data gets removed, and the new trade volume gets added to
        the most recent hour.
    - It then updates the pairVolume map with the new VolumeWindow for that trading pair.

Calculating Total Volume 24h (getPairVolumes function):
    - This function computes the total trading volume for each pair in the last 24 hours.
    - It iterates over each entry in pairVolume, sums up the volumes from each hour in the window, and returns these totals along with the
        corresponding pair names.

Handling Upgrades:
    - preupgrade and postupgrade functions ensure that the volume data persists across code upgrades of the actor. Before an upgrade, data is
        saved into pairsVolumeEntries, and after the upgrade, it's restored from there back into the pairVolume map.

In the context of an Internet Computer canister, several concerns typical in other environments are inherently addressed. First, the time 
is consistently managed by the system, ensuring that the Time.Time values used in the algorithm are reliable and cannot be lower than the previous values.
Concurrency is also inherently managed by the Internet Computer's architecture, eliminating the risk of race conditions or inconsistencies due to concurrent updates.
Furthermore, the algorithm is designed to account for periods with no trades; it won't update the volume records until a new trade occurs. 
When a new trade is recorded after a gap, the algorithm adjusts the volume window accordingly, ensuring that the reported volumes remain accurate. 
This design effectively maintains a rolling 24-hour volume window, even across periods of inactivity, and updates it precisely when new trade data is available.

In summary, this algorithm efficiently tracks and updates trading volumes for various pairs on an hourly basis over a rolling 24-hour period.

How to add:
    // Place this line in the _swap function https://github.com/sonicdex/sonic-v1/blob/c5caf4b0adff117d6fcce01ed1f680b8026a2033/sonic-v1/swap/src/swap.mo#L2080C14-L2080C14
    // Note: It should only add the amount in one of the two tokens (always the first one according to configuration) to the volume
```
updateVolume(pairid, Time.now(), volume)
```

the rest of the code can be copy pasted and should work fine. Don't include the testUpdateVolume function


## Tests

Tests are in test.blast You will need Internet Base VScode extension to open them.
![image](https://github.com/infu/sonic_contrib_volume/assets/24810/e8087604-46be-4a7b-b50d-a3ac130af074)
![image](https://github.com/infu/sonic_contrib_volume/assets/24810/19773f72-9ce5-42c5-b658-f58a19686003)

