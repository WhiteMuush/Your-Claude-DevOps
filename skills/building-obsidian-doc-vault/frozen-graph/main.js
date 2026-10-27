// Obsidian plugin that keeps every graph node where it was frozen.
const { Plugin, Notice } = require('obsidian');

// Checked on every frame: stable after 10 frames without a new node, gives up after about 3 seconds.
const NODE_CHECKS = { stableChecks: 10, maxChecks: 180 };

function readPositions(nodes) {
    const positions = {};
    for (const node of nodes) positions[node.id] = { x: node.x, y: node.y };
    return positions;
}

// Plugin messages go through the worker's original channel, so they are never taken for a mouse gesture.
function send(renderer, message) {
    const worker = renderer.worker;
    if (worker.frozenGraphSend) worker.frozenGraphSend(message);
    else worker.postMessage(message);
}

function pinAll(renderer, positions) {
    for (const [id, pos] of Object.entries(positions)) {
        send(renderer, { forceNode: { id, x: pos.x, y: pos.y } });
    }
}

function pinAppearing(renderer, positions, pinned, total = Object.keys(positions).length) {
    if (pinned.size >= total) return;
    for (const node of renderer.nodes) {
        const pos = positions[node.id];
        if (!pos || pinned.has(node.id)) continue;
        send(renderer, { forceNode: { id: node.id, x: pos.x, y: pos.y } });
        pinned.add(node.id);
    }
}

function releaseAll(renderer, positions) {
    for (const id of Object.keys(positions)) {
        send(renderer, { forceNode: { id, x: null, y: null } });
    }
}

// While a node is dragged the whole graph comes alive, then it is frozen again where it stands on drop.
function followDrags(renderer, getPositions, onDrop) {
    const worker = renderer.worker;
    if (worker.frozenGraphSend) return;
    const post = worker.postMessage.bind(worker);
    worker.frozenGraphSend = post;
    let dragging = false;

    worker.postMessage = (message) => {
        const force = message && message.forceNode;
        const positions = getPositions();
        if (!force || Object.keys(positions).length === 0) {
            post(message);
            return;
        }

        const dropped = force.x === null && force.y === null;
        if (!dropped && !dragging) {
            dragging = true;
            releaseAll(renderer, Object.fromEntries(Object.entries(positions).filter(([id]) => id !== force.id)));
        } else if (dropped && dragging) {
            dragging = false;
            const current = readPositions(renderer.nodes);
            pinAll(renderer, current);
            onDrop(current);
            return;
        }
        post(message);
    };
}

// The graph creates its nodes little by little: onCheck runs on every pass, onDone once their count stops moving.
function untilNodesStable(renderer, onCheck, onDone, schedule = (fn) => requestAnimationFrame(fn), limits = NODE_CHECKS) {
    let last = -1;
    let same = 0;
    let checks = 0;

    const check = () => {
        checks++;
        onCheck();
        const count = renderer.nodes.length;
        same = count > 0 && count === last ? same + 1 : 0;
        last = count;
        if (same >= limits.stableChecks || checks >= limits.maxChecks) {
            onDone();
            return;
        }
        schedule(check);
    };
    schedule(check);
}

class FrozenGraph extends Plugin {
    async onload() {
        const data = await this.loadData();
        this.positions = (data && data.positions) || {};

        this.addCommand({ id: 'freeze', name: 'Freeze the graph', callback: () => this.freeze() });
        this.addCommand({ id: 'release', name: 'Release the graph', callback: () => this.release() });
        this.registerEvent(this.app.workspace.on('layout-change', () => this.restoreGraphs()));
        this.registerEvent(this.app.vault.on('rename', (file, oldPath) => this.rename(oldPath, file.path)));
        this.app.workspace.onLayoutReady(() => this.restoreGraphs());
    }

    graphViews() {
        return this.app.workspace
            .getLeavesOfType('graph')
            .map((leaf) => leaf.view)
            .filter((view) => view && view.renderer && view.renderer.worker && Array.isArray(view.renderer.nodes));
    }

    renderers() {
        return this.graphViews().map((view) => view.renderer);
    }

    restoreGraphs() {
        for (const view of this.graphViews()) {
            const renderer = view.renderer;
            followDrags(renderer, () => this.positions, (positions) => {
                this.positions = positions;
                this.save();
            });
            if (renderer.frozenGraphRestored) continue;
            renderer.frozenGraphRestored = true;
            if (Object.keys(this.positions).length === 0) continue;

            // The graph stays hidden while nodes are put back, so the opening burst is never seen.
            view.contentEl.style.opacity = '0';
            const pinned = new Set();
            const total = Object.keys(this.positions).length;
            untilNodesStable(
                renderer,
                () => pinAppearing(renderer, this.positions, pinned, total),
                () => (view.contentEl.style.opacity = ''),
            );
        }
    }

    async freeze() {
        const [renderer] = this.renderers();
        if (!renderer) {
            new Notice('Open the graph before freezing it.');
            return;
        }
        this.positions = readPositions(renderer.nodes);
        pinAll(renderer, this.positions);
        await this.save();
        new Notice(`Graph frozen: ${Object.keys(this.positions).length} notes.`);
    }

    async release() {
        const previous = this.positions;
        this.positions = {};
        for (const renderer of this.renderers()) releaseAll(renderer, previous);
        await this.save();
        new Notice('Graph released.');
    }

    async rename(oldPath, newPath) {
        if (!this.positions[oldPath]) return;
        this.positions[newPath] = this.positions[oldPath];
        delete this.positions[oldPath];
        await this.save();
    }

    save() {
        return this.saveData({ positions: this.positions });
    }
}

FrozenGraph.helpers = { readPositions, pinAll, pinAppearing, releaseAll, followDrags, untilNodesStable };
module.exports = FrozenGraph;
