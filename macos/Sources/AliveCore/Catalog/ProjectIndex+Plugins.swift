// Port of src/ProjectIndex.cs (RefreshInstalled, Health, KnownVendors, AcceptVendor, PluginUsage)
import Foundation

extension ProjectIndex {
    /// Re-reads the inventory of installed plugins and marks each set with how many plugins it is
    /// missing. Called after a scan and from the "refresh" button — the set of plugins changes
    /// without the sets being edited.
    ///
    /// Missing plugins are a state, not an error: nothing is logged per plugin, one summary line
    /// per refresh. When the inventory is unavailable (nothing could be read) no plugin is called
    /// missing at all — `missingPlugins` stays 0 for every set.
    public func refreshInstalled() {
        let inv = inventoryLoader(settings)
        // The matching is CPU-heavy on a big catalog, so it runs on a snapshot outside the lock
        // (readers on the main thread must not wait for it); the result is swapped in under the
        // lock only if no scan has published in the meantime, else it is redone on the new list.
        var missingNames = Set<String>(), affected = 0
        for attempt in 0..<4 {
            lock.lock()
            let generation = _generation, snapshot = _sets
            lock.unlock()
            let counts = attempt < 3 ? Self.missingCounts(snapshot, inv) : nil
            lock.lock()
            if let counts, generation == _generation {
                var updated = snapshot
                for i in updated.indices { updated[i].missingPlugins = counts.perSet[i] }
                _inventory = inv
                _sets = updated
                _generation += 1    // the vendor list and the plugin summary depend on what is installed
                lock.unlock()
                missingNames = counts.names; affected = counts.affected
                break
            }
            if counts == nil {      // the catalog keeps changing: settle it under the lock, once
                let last = Self.missingCounts(_sets, inv)
                for i in _sets.indices { _sets[i].missingPlugins = last.perSet[i] }
                _inventory = inv
                _generation += 1
                lock.unlock()
                missingNames = last.names; affected = last.affected
                break
            }
            lock.unlock()
        }

        if inv.isAvailable {
            Diag.info("plugins: \(inv.all.count) installed (\(inv.sources.joined(separator: ", "))); "
                      + "\(missingNames.count) used plugins not installed, in \(affected) sets")
        } else {
            Diag.info("plugins: inventory unavailable (\(inv.error ?? "nothing found")); missing plugins not reported")
        }
    }

    private struct MissingCounts { var perSet: [Int] = []; var names = Set<String>(); var affected = 0 }

    private static func missingCounts(_ sets: [SetEntry], _ inv: PluginInventory) -> MissingCounts {
        var out = MissingCounts()
        out.perSet.reserveCapacity(sets.count)
        for e in sets {
            var missing = 0
            if inv.isAvailable {
                for (k, name) in e.plugins.enumerated() {
                    let uid = k < e.pluginUids.count ? e.pluginUids[k] : ""
                    if inv.match(uid: uid, name: name).kind == .missing { missing += 1; out.names.insert(name.lowercased()) }
                }
            }
            if missing > 0 { out.affected += 1 }
            out.perSet.append(missing)
        }
        return out
    }

    /// The catalog and the inventory as one value, taken under one lock: what a derivation (the
    /// plugin table, the health cards) must be built from, so it never mixes two catalogs.
    public struct PluginSnapshot: Sendable {
        public let generation: Int
        public let sets: [SetEntry]
        public let inventory: PluginInventory
    }

    public func pluginSnapshot() -> PluginSnapshot {
        lock.lock(); defer { lock.unlock() }
        return PluginSnapshot(generation: _generation, sets: _sets, inventory: _inventory)
    }

    /// Bumps whenever the sets or the inventory change.
    public var generation: Int { lock.lock(); defer { lock.unlock() }; return _generation }

    public func health(_ usage: [PluginStat]) -> PluginHealth {
        health(usage, inventory: inventory)
    }

    public func health(_ usage: [PluginStat], inventory inv: PluginInventory) -> PluginHealth {
        var h = PluginHealth()
        h.installedTotal = inv.all.count
        h.filesGone = inv.all.filter(\.fileMissing).count
        // We count by the same rows that are visible in the list: two separate counts of one and
        // the same thing inevitably drift apart.
        for st in usage {
            if st.isUnused { h.installedUnused += 1; continue }
            h.used += 1
            switch st.match {
            case .exact: h.installed += 1
            case .otherFormat: h.otherFormat += 1
            case .missing: h.missing += 1
            case .unknown: break        // the inventory is unavailable: not counted as anything
            }
        }
        return h
    }

    /// The names that have turned up at least once as a genuine vendor (the VST3:Vendor:Name
    /// form, or an AU's Manufacturer field). Vendors from the inventory are above suspicion: if
    /// "Arturia" is there, a browser folder by that name is no invention either.
    public var knownVendors: Set<String> { knownVendors(in: pluginSnapshot()) }

    func knownVendors(in snap: PluginSnapshot) -> Set<String> {
        lock.lock()
        if let c = _vendorCache, c.generation == snap.generation { lock.unlock(); return c.set }
        lock.unlock()
        let generation = snap.generation, sets = snap.sets, inv = snap.inventory

        var names = Set<String>()
        for p in inv.all where !p.vendor.isEmpty { names.insert(p.vendor.lowercased()) }
        for e in sets {
            for (i, v) in e.pluginVendors.enumerated()
            where !v.isEmpty && i < e.pluginVendorConfident.count && e.pluginVendorConfident[i] {
                names.insert(v.lowercased())
            }
        }
        lock.lock(); _vendorCache = (generation, names); lock.unlock()
        return names
    }

    /// For VST2 the browser path holds a folder rather than a developer, and in a collection
    /// sorted into folders "Eff" or "Gen" comes flying out of it. So an unreliable name is
    /// accepted only if it has been confirmed somewhere as a genuine vendor — "Arturia" passes,
    /// "Eff" does not.
    public func acceptVendor(_ vendor: String, confident: Bool) -> String {
        if vendor.isEmpty || confident { return vendor }
        return knownVendors.contains(vendor.lowercased()) ? vendor : ""
    }

    private func acceptVendor(_ vendor: String, confident: Bool, known: Set<String>) -> String {
        if vendor.isEmpty || confident { return vendor }
        return known.contains(vendor.lowercased()) ? vendor : ""
    }

    /// A summary of the plugins: the name, the developer, how many sets it occurs in and whether
    /// it is on the machine. What is installed but used nowhere gets into the list too —
    /// otherwise such plugins cannot be found at all. Remembered per catalog/inventory snapshot:
    /// it is asked for on every keystroke in the plugins tab.
    public func pluginUsage() -> [PluginStat] {
        pluginUsage(of: pluginSnapshot()) ?? []
    }

    /// The same, derived from one snapshot (see `pluginSnapshot()`) and nothing else, so a
    /// scan publishing meanwhile cannot mix into it. Polls `isCancelled` between sets and
    /// plugins; nil when it turned true (nothing is remembered then).
    public func pluginUsage(of snap: PluginSnapshot, isCancelled: () -> Bool = { false }) -> [PluginStat]? {
        lock.lock()
        if let c = _usageCache, c.generation == snap.generation { lock.unlock(); return c.list }
        lock.unlock()

        let known = knownVendors(in: snap)
        guard var use = usedPlugins(snap.sets, known: known, isCancelled: isCancelled) else { return nil }
        crossCheck(&use, with: snap.inventory)
        var list = Array(use.values) + unusedPlugins(snap.inventory, used: use)
        list.sort {
            $0.sets != $1.sets ? $0.sets > $1.sets
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if isCancelled() { return nil }
        lock.lock(); _usageCache = (snap.generation, list); lock.unlock()
        return list
    }

    private func usedPlugins(_ sets: [SetEntry], known: Set<String>,
                             isCancelled: () -> Bool) -> [String: PluginStat]? {
        var use: [String: PluginStat] = [:]
        for (n, e) in sets.enumerated() {
            if n % 256 == 0, isCancelled() { return nil }
            for (i, name) in e.plugins.enumerated() {
                let rawConf = i < e.pluginVendorConfident.count && e.pluginVendorConfident[i]
                let vendor = acceptVendor(i < e.pluginVendors.count ? e.pluginVendors[i] : "", confident: rawConf,
                                          known: known)
                var st = use[name.lowercased()] ?? PluginStat()
                if st.name.isEmpty { st.name = name }
                st.sets += 1
                if st.uid.isEmpty, i < e.pluginUids.count { st.uid = e.pluginUids[i] }
                // The developer is not known in every set. A reliable source (VST3/AU) displaces
                // a browser folder name found earlier.
                if !vendor.isEmpty, st.vendor.isEmpty || (rawConf && !st.vendorConfident) {
                    st.vendor = vendor
                    st.vendorConfident = rawConf
                }
                use[name.lowercased()] = st
            }
        }
        return use
    }

    /// Cross-check against what is installed and take the vendor from there: the inventory's is
    /// genuine, while a VST2's browser path slips in a folder name like "Eff".
    private func crossCheck(_ use: inout [String: PluginStat], with inv: PluginInventory) {
        for key in use.keys {
            guard var st = use[key] else { continue }
            let m = inv.match(uid: st.uid, name: st.name)
            st.match = m.kind
            st.installed = m.plugin
            if m.kind == .exact, let p = m.plugin, !p.vendor.isEmpty {
                st.vendor = p.vendor
                st.vendorConfident = true
            }
            use[key] = st
        }
    }

    /// Installed but met in no set at all — candidates for removal. "Met" is counted by the same
    /// signs as a match in general: one and the same plugin may be registered both as VST2 and as
    /// VST3, and if a set asks for the VST2 version then the VST3 twin is in use too.
    private func unusedPlugins(_ inv: PluginInventory, used: [String: PluginStat]) -> [PluginStat] {
        var usedUids = Set<String>(), usedNames = Set<String>()
        for st in used.values {
            if !st.uid.isEmpty { usedUids.insert(st.uid.lowercased()) }
            usedNames.insert(PluginInventory.normalize(st.name))
        }
        var out: [PluginStat] = []
        for p in inv.all {
            if usedUids.contains(p.uid.lowercased()) { continue }
            if usedNames.contains(PluginInventory.normalize(p.name)) { continue }
            if usedNames.contains(PluginInventory.normalize(p.vendor + p.name)) { continue }
            var st = PluginStat()
            st.name = p.name
            st.vendor = p.vendor
            st.vendorConfident = true
            st.uid = p.uid
            st.installed = p
            st.match = .exact
            out.append(st)
        }
        return out
    }
}
