// Tests du plugin Graphe figé, avec un faux module obsidian et un faux moteur de graphe.
const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');

const originalLoad = Module._load;
Module._load = function (request, ...rest) {
    if (request === 'obsidian') return { Plugin: class {}, Notice: class {} };
    return originalLoad.call(this, request, ...rest);
};

const GrapheFige = require(process.env.PLUGIN_MAIN || require('node:path').join(__dirname, 'main.js'));
const { readPositions, pinAll, pinAppearing, releaseAll, followDrags, untilNodesStable } = GrapheFige.helpers;

function fakeRenderer(nodes) {
    const sent = [];
    return { nodes, sent, worker: { postMessage: (m) => sent.push(m) } };
}

function makeNodes(count) {
    return Array.from({ length: count }, (_, i) => ({ id: `${i}.md`, x: 0, y: 0 }));
}

test('readPositions garde id, x et y de chaque nœud', () => {
    const nodes = [{ id: 'A.md', x: 1, y: 2, extra: true }, { id: 'B.md', x: -3, y: 4 }];
    assert.deepEqual(readPositions(nodes), { 'A.md': { x: 1, y: 2 }, 'B.md': { x: -3, y: 4 } });
});

test('pinAll bloque chaque nœud enregistré à sa position', () => {
    const r = fakeRenderer([]);
    pinAll(r, { 'A.md': { x: 1, y: 2 } });
    assert.deepEqual(r.sent, [{ forceNode: { id: 'A.md', x: 1, y: 2 } }]);
});

test('pinAppearing bloque seulement les nœuds présents et enregistrés', () => {
    const r = fakeRenderer([{ id: 'A.md', x: 0, y: 0 }, { id: 'Nouveau.md', x: 0, y: 0 }]);
    const pinned = new Set();
    pinAppearing(r, { 'A.md': { x: 1, y: 2 }, 'Absent.md': { x: 3, y: 4 } }, pinned);

    assert.deepEqual(r.sent, [{ forceNode: { id: 'A.md', x: 1, y: 2 } }]);
    assert.deepEqual([...pinned], ['A.md']);
});

test('pinAppearing ne rebloque pas un nœud déjà bloqué', () => {
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

test('releaseAll libère chaque nœud enregistré', () => {
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

test('tirer une note libère toutes les autres', () => {
    const { r } = frozenRenderer();
    r.worker.postMessage({ forceNode: { id: 'A.md', x: 5, y: 5 } });

    assert.deepEqual(r.sent, [
        { forceNode: { id: 'B.md', x: null, y: null } },
        { forceNode: { id: 'C.md', x: null, y: null } },
        { forceNode: { id: 'A.md', x: 5, y: 5 } },
    ]);
});

test('la suite du même tirage ne relibère pas les autres', () => {
    const { r } = frozenRenderer();
    r.worker.postMessage({ forceNode: { id: 'A.md', x: 5, y: 5 } });
    r.sent.length = 0;
    r.worker.postMessage({ forceNode: { id: 'A.md', x: 6, y: 6 } });

    assert.deepEqual(r.sent, [{ forceNode: { id: 'A.md', x: 6, y: 6 } }]);
});

test('lâcher la note refige tout à la position courante et enregistre', () => {
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

test('un graphe non figé laisse passer tous les messages', () => {
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

test('les messages du plugin ne sont pas pris pour un tirage', () => {
    const { r, state } = frozenRenderer();
    pinAll(r, state.positions);
    releaseAll(r, state.positions);

    assert.equal(r.sent.length, 6);
    assert.deepEqual(state.drops, []);
});

test('followDrags ne patche le worker qu\'une fois', () => {
    const { r, state } = frozenRenderer();
    followDrags(r, () => state.positions, () => {});
    r.worker.postMessage({ forceNode: { id: 'A.md', x: 5, y: 5 } });

    assert.equal(r.sent.length, 3);
});

test('untilNodesStable appelle onCheck à chaque passage et onDone une fois stable', () => {
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

test('untilNodesStable appelle quand même onDone après trop d\'essais', () => {
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

test('pinAppearing ne relit plus les nœuds une fois tout bloqué', () => {
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
