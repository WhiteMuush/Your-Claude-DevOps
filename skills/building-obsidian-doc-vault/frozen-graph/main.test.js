// Tests for the Frozen Graph plugin, with a fake obsidian module and a fake graph engine.
const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');

const originalLoad = Module._load;
Module._load = function (request, ...rest) {
    if (request === 'obsidian') return { Plugin: class {}, Notice: class {} };
    return originalLoad.call(this, request, ...rest);
};

const FrozenGraph = require(process.env.PLUGIN_MAIN || require('node:path').join(__dirname, 'main.js'));
const { readPositions, pinAll, pinAppearing, releaseAll, followDrags, untilNodesStable } = FrozenGraph.helpers;

function fakeRenderer(nodes) {
    const sent = [];
    return { nodes, sent, worker: { postMessage: (m) => sent.push(m) } };
}

function makeNodes(count) {
    return Array.from({ length: count }, (_, i) => ({ id: `${i}.md`, x: 0, y: 0 }));
}

test('readPositions keeps id, x and y of every node', () => {
    const nodes = [{ id: 'A.md', x: 1, y: 2, extra: true }, { id: 'B.md', x: -3, y: 4 }];
    assert.deepEqual(readPositions(nodes), { 'A.md': { x: 1, y: 2 }, 'B.md': { x: -3, y: 4 } });
});

test('pinAll pins every saved node at its position', () => {
    const r = fakeRenderer([]);
    pinAll(r, { 'A.md': { x: 1, y: 2 } });
    assert.deepEqual(r.sent, [{ forceNode: { id: 'A.md', x: 1, y: 2 } }]);
});

test('pinAppearing pins only nodes that are both present and saved', () => {
    const r = fakeRenderer([{ id: 'A.md', x: 0, y: 0 }, { id: 'New.md', x: 0, y: 0 }]);
    const pinned = new Set();
    pinAppearing(r, { 'A.md': { x: 1, y: 2 }, 'Missing.md': { x: 3, y: 4 } }, pinned);

    assert.deepEqual(r.sent, [{ forceNode: { id: 'A.md', x: 1, y: 2 } }]);
    assert.deepEqual([...pinned], ['A.md']);
});

test('pinAppearing never pins the same node twice', () => {
    const r = fakeRenderer([{ id: 'A.md', x: 0, y: 0 }]);
    const pinned = new Set();
    const positions = { 'A.md': { x: 1, y: 2 }, 'B.md': { x: 3, y: 4 } };
    pinAppearing(r, positions, pinned);
    r.nodes.push({ id: 'B.md', x: 0, y: 0 });
    pinAppearing(r, positions, pinned);

    assert.deepEqual(r.sent, [
        { forceNode: { id: 'A.md', x: 1, y: 2 } },
        { forceNode: { id: 'B.md', x: 3, y: 4 } },
    ]);
});

test('releaseAll releases every saved node', () => {
    const r = fakeRenderer([]);
    releaseAll(r, { 'A.md': { x: 1, y: 2 } });
    assert.deepEqual(r.sent, [{ forceNode: { id: 'A.md', x: null, y: null } }]);
});

function frozenRenderer() {
    const r = fakeRenderer([{ id: 'A.md', x: 1, y: 1 }, { id: 'B.md', x: 2, y: 2 }, { id: 'C.md', x: 3, y: 3 }]);
    const state = { positions: readPositions(r.nodes), drops: [] };
    followDrags(r, () => state.positions, (positions) => state.drops.push(positions));
    return { r, state };
}

test('dragging a node releases all the others', () => {
    const { r } = frozenRenderer();
    r.worker.postMessage({ forceNode: { id: 'A.md', x: 5, y: 5 } });

    assert.deepEqual(r.sent, [
        { forceNode: { id: 'B.md', x: null, y: null } },
        { forceNode: { id: 'C.md', x: null, y: null } },
        { forceNode: { id: 'A.md', x: 5, y: 5 } },
    ]);
});

test('the rest of the same drag does not release them again', () => {
    const { r } = frozenRenderer();
    r.worker.postMessage({ forceNode: { id: 'A.md', x: 5, y: 5 } });
    r.sent.length = 0;
    r.worker.postMessage({ forceNode: { id: 'A.md', x: 6, y: 6 } });

    assert.deepEqual(r.sent, [{ forceNode: { id: 'A.md', x: 6, y: 6 } }]);
});

test('dropping the node freezes everything where it stands and saves', () => {
    const { r, state } = frozenRenderer();
    r.worker.postMessage({ forceNode: { id: 'A.md', x: 5, y: 5 } });
    r.nodes = [{ id: 'A.md', x: 10, y: 10 }, { id: 'B.md', x: 20, y: 20 }, { id: 'C.md', x: 30, y: 30 }];
    r.sent.length = 0;

    r.worker.postMessage({ forceNode: { id: 'A.md', x: null, y: null } });

    assert.deepEqual(r.sent, [
        { forceNode: { id: 'A.md', x: 10, y: 10 } },
        { forceNode: { id: 'B.md', x: 20, y: 20 } },
        { forceNode: { id: 'C.md', x: 30, y: 30 } },
    ]);
    assert.deepEqual(state.drops, [{ 'A.md': { x: 10, y: 10 }, 'B.md': { x: 20, y: 20 }, 'C.md': { x: 30, y: 30 } }]);
});

test('a graph that was never frozen lets every message through', () => {
    const r = fakeRenderer([{ id: 'A.md', x: 1, y: 1 }]);
    const drops = [];
    followDrags(r, () => ({}), (positions) => drops.push(positions));

    r.worker.postMessage({ forceNode: { id: 'A.md', x: 5, y: 5 } });
    r.worker.postMessage({ forceNode: { id: 'A.md', x: null, y: null } });

    assert.deepEqual(r.sent, [
        { forceNode: { id: 'A.md', x: 5, y: 5 } },
        { forceNode: { id: 'A.md', x: null, y: null } },
    ]);
    assert.deepEqual(drops, []);
});

test('plugin messages are never taken for a drag', () => {
    const { r, state } = frozenRenderer();
    pinAll(r, state.positions);
    releaseAll(r, state.positions);

    assert.equal(r.sent.length, 6);
    assert.deepEqual(state.drops, []);
});

test('followDrags patches the worker only once', () => {
    const { r, state } = frozenRenderer();
    followDrags(r, () => state.positions, () => {});
    r.worker.postMessage({ forceNode: { id: 'A.md', x: 5, y: 5 } });

    assert.equal(r.sent.length, 3);
});

test('untilNodesStable calls onCheck on every pass and onDone once stable', () => {
    const r = fakeRenderer([]);
    const queue = [];
    let checks = 0;
    let done = 0;
    untilNodesStable(r, () => checks++, () => done++, (fn) => queue.push(fn), { stableChecks: 3, maxChecks: 30 });

    for (const n of [0, 2, 5, 5, 5, 5]) {
        r.nodes = makeNodes(n);
        queue.shift()();
    }

    assert.equal(checks, 6);
    assert.equal(done, 1);
    assert.equal(queue.length, 0);
});

test('untilNodesStable still calls onDone after too many checks', () => {
    const r = fakeRenderer([]);
    const queue = [];
    let done = 0;
    untilNodesStable(r, () => {}, () => done++, (fn) => queue.push(fn), { stableChecks: 3, maxChecks: 30 });

    for (let i = 0; queue.length > 0 && i < 100; i++) {
        r.nodes = makeNodes(i);
        queue.shift()();
    }

    assert.equal(done, 1);
    assert.equal(queue.length, 0);
});

test('pinAppearing stops reading nodes once everything is pinned', () => {
    let reads = 0;
    const nodes = [{ id: 'A.md', x: 0, y: 0 }];
    const r = { sent: [], worker: { postMessage: () => {} } };
    Object.defineProperty(r, 'nodes', { get: () => { reads++; return nodes; } });
    const pinned = new Set();
    const positions = { 'A.md': { x: 1, y: 2 } };

    pinAppearing(r, positions, pinned, 1);
    const afterFirst = reads;
    pinAppearing(r, positions, pinned, 1);

    assert.equal(reads, afterFirst);
});
