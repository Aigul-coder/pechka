(() => {
  const { Engine, World, Bodies, Body, Constraint, Events, Mouse, MouseConstraint } = Matter;

  const BRICK_W = 78;
  const BRICK_H = 34;
  const MORTAR = 2;
  const JOINT_GAP = 18;
  const CELL_W = BRICK_W + MORTAR;
  const CELL_H = BRICK_H + MORTAR;
  const PIPE_W = 28;
  const PIPE_H = 86;
  const PROP_THICK = 20;
  const PROP_LEN = 5 * CELL_H;
  const FOUNDATION_W = 4 * CELL_W + 18;
  const UI_LEFT = 300;
  const UI_RIGHT = 220;

  const CAT_GROUND = 0x0001;
  const CAT_BRICK = 0x0002;
  const CAT_FUEL = 0x0004;
  const CAT_PROP = 0x0008;
  const MASK_SOLID = CAT_GROUND | CAT_BRICK | CAT_FUEL | CAT_PROP;

  const TOOL = {
    HAND: "hand",
    BRICK: "brick",
    CEMENT: "cement",
    SAWDUST: "sawdust",
    MATCH: "match",
    PIPE: "pipe",
    PROP: "prop",
    STOVE: "stove",
  };

  const STOVES = {
    small: {
      name: "Малая",
      running: false,
      originCol: 1,
      bricks: [
        [0, 0], [1, 0], [2, 0],
        [0, 1], [2, 1],
        [0, 2], [1, 2], [2, 2],
      ],
      pipe: { col: 2, row: 3 },
    },
    russian: {
      name: "Русская",
      running: false,
      originCol: 2,
      bricks: [
        [0, 0], [1, 0], [2, 0], [3, 0], [4, 0],
        [0, 1], [4, 1],
        [0, 2], [4, 2],
        [0, 3], [1, 3], [2, 3], [3, 3], [4, 3],
      ],
      pipe: { col: 4, row: 4 },
    },
    dutch: {
      name: "Голландка",
      running: false,
      originCol: 1,
      bricks: [
        [0, 0], [1, 0], [2, 0],
        [0, 1], [2, 1],
        [0, 2], [1, 2], [2, 2],
        [0, 3], [2, 3],
        [0, 4], [1, 4], [2, 4],
      ],
      pipe: { col: 1, row: 5 },
    },
    potbelly: {
      name: "Буржуйка",
      running: false,
      originCol: 1,
      bricks: [
        [0, 0], [1, 0], [2, 0],
        [0, 1], [2, 1],
        [0, 2], [1, 2], [2, 2],
      ],
      pipe: { col: 1, row: 3 },
    },
  };

  const canvas = document.getElementById("game");
  const ctx = canvas.getContext("2d");
  const hintEl = document.getElementById("hint");
  const sealFill = document.getElementById("seal-fill");
  const sealValue = document.getElementById("seal-value");
  const jointValue = document.getElementById("joint-value");
  const tempFill = document.getElementById("temp-fill");
  const tempValue = document.getElementById("temp-value");
  const bondLabel = document.getElementById("bond-label");
  const snapLabel = document.getElementById("snap-label");
  const intro = document.getElementById("intro");

  const state = {
    tool: TOOL.BRICK,
    runningBond: true,
    snap: true,
    rotated: false,
    started: false,
    pointer: { x: 0, y: 0, down: false },
    hoverJoint: null,
    camera: { x: 0, y: 0, zoom: 1 },
    particles: [],
    smoke: [],
    ashes: [],
    joints: [],
    bricksList: [],
    fuels: [],
    pipeList: [],
    props: [],
    matches: [],
    temp: 20,
    time: 0,
    lastPour: -999,
    stoveId: "russian",
  };

  const hints = {
    hand: "Тащи кирпичи, трубы и деревянные подпорки.",
    brick: "Клади кирпич. Сквозь него дым не идёт. Если не держится — поставь подпорку.",
    cement: "Кликни по стыку. Цемент схватывает кирпичи и приделывает трубу к кладке.",
    sawdust: "Сыпь мелкие опилки струёй. Они осыпаются и текут кучей.",
    match: "Горящая спичка. Кликни по опилкам или брось её — и подпорку тоже.",
    pipe: "Дымоход. Прихвати цементом к кирпичу. Всасывает дым, только если до устья нет стены.",
    prop: "Подпорка как 5 кирпичей сбоку. Горит. R — положить плашмя.",
    stove: "Кликни — встанет готовая печка целиком: кирпичи, цемент и труба.",
  };

  let width = 0;
  let height = 0;
  let groundY = 0;
  let originX = 0;
  let roomCanvas = null;

  const GRAVITY_G = 1;
  const GRAVITY_MULT = 8;
  const PHYS_SUBSTEPS = 6;
  const ASH_CAP = 720;
  const texCache = new Map();

  const engine = Engine.create({ gravity: { x: 0, y: GRAVITY_G * GRAVITY_MULT } });
  const world = engine.world;
  engine.enableSleeping = true;
  engine.positionIterations = 28;
  engine.velocityIterations = 22;
  engine.constraintIterations = 10;

  const ground = Bodies.rectangle(0, 0, 3600, 140, {
    isStatic: true,
    friction: 1,
    restitution: 0,
    collisionFilter: { category: CAT_GROUND, mask: CAT_BRICK | CAT_FUEL | CAT_PROP },
    label: "ground",
  });

  const foundation = Bodies.rectangle(0, 0, FOUNDATION_W, 28, {
    isStatic: true,
    friction: 1.2,
    restitution: 0,
    collisionFilter: { category: CAT_GROUND, mask: CAT_BRICK | CAT_FUEL | CAT_PROP },
    label: "foundation",
  });

  World.add(world, [ground, foundation]);

  const mouse = Mouse.create(canvas);
  const mouseConstraint = MouseConstraint.create(engine, {
    mouse,
    constraint: { stiffness: 0.42, damping: 0.2, render: { visible: false } },
  });
  mouseConstraint.collisionFilter.mask = CAT_BRICK | CAT_FUEL | CAT_PROP;
  World.add(world, mouseConstraint);
  setMouseEnabled(false);

  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 3);
    width = window.innerWidth;
    height = window.innerHeight;
    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = "high";
    mouse.pixelRatio = dpr;

    groundY = height - 96;
    originX = UI_LEFT + (width - UI_LEFT - UI_RIGHT) / 2;
    Body.setPosition(ground, { x: originX, y: groundY + 78 });
    Body.setPosition(foundation, { x: originX, y: groundY - 6 });
    roomCanvas = null;
    syncMouse();
  }

  function syncMouse() {
    mouse.offset.x = width / 2 - (width / 2 + state.camera.x) * state.camera.zoom;
    mouse.offset.y = height / 2 - (height / 2 + state.camera.y) * state.camera.zoom;
    mouse.scale.x = 1 / state.camera.zoom;
    mouse.scale.y = 1 / state.camera.zoom;
  }

  function setMouseEnabled(on) {
    mouseConstraint.collisionFilter.mask = on ? CAT_BRICK | CAT_FUEL | CAT_PROP : 0;
    mouseConstraint.constraint.stiffness = on ? 0.42 : 0;
  }

  function setTool(tool) {
    state.tool = tool;
    document.querySelectorAll(".tool[data-tool]").forEach((btn) => {
      btn.classList.toggle("active", btn.dataset.tool === tool);
    });
    document.querySelectorAll(".catalog button").forEach((btn) => {
      btn.classList.toggle("active", tool === TOOL.STOVE && btn.dataset.stove === state.stoveId);
    });
    hintEl.textContent = hints[tool];
    setMouseEnabled(tool === TOOL.HAND);
  }

  function selectStove(id) {
    if (!STOVES[id]) return;
    state.stoveId = id;
    setTool(TOOL.STOVE);
    hintEl.textContent = `${STOVES[id].name}: кликни на площадку — печка встанет целиком.`;
  }

  function brickSize() {
    return state.rotated ? { w: BRICK_H, h: BRICK_W } : { w: BRICK_W, h: BRICK_H };
  }

  function cellPos(col, row, running = true) {
    const offset = running && row % 2 ? CELL_W / 2 : 0;
    return {
      x: originX + (col - 2) * CELL_W + offset,
      y: groundY - 20 - BRICK_H / 2 - row * CELL_H,
    };
  }

  function snapPoint(x, y, w, h) {
    const row = Math.max(0, Math.round((groundY - 20 - y) / CELL_H));
    const offset = state.runningBond && row % 2 ? CELL_W / 2 : 0;
    const col = Math.round((x - originX - offset) / CELL_W + 2);
    return {
      x: originX + (col - 2) * CELL_W + offset,
      y: groundY - 20 - h / 2 - row * CELL_H,
      row,
      col,
    };
  }

  function placePoint(x, y, w, h) {
    if (!state.snap) return { x, y };
    return snapPoint(x, y, w, h);
  }

  function hash(n) {
    let x = (n * 374761393) >>> 0;
    return () => {
      x ^= x << 13;
      x ^= x >>> 17;
      x ^= x << 5;
      return (x >>> 0) / 4294967295;
    };
  }

  function bodiesForPlace() {
    return [...state.bricksList, ...state.pipeList, ...state.props];
  }

  function insideSolid(x, y) {
    return bodiesForPlace().some((body) => {
      const b = body.bounds;
      return x > b.min.x + 3 && x < b.max.x - 3 && y > b.min.y + 3 && y < b.max.y - 3;
    });
  }

  function canPlace(x, y, w, h) {
    const probe = { min: { x: x - w / 2 + 3, y: y - h / 2 + 3 }, max: { x: x + w / 2 - 3, y: y + h / 2 - 3 } };
    return bodiesForPlace().every((body) => {
      const b = body.bounds;
      return !(probe.min.x < b.max.x && probe.max.x > b.min.x && probe.min.y < b.max.y && probe.max.y > b.min.y);
    });
  }

  function spawnBrick(x, y, options = {}) {
    const w = options.w ?? brickSize().w;
    const h = options.h ?? brickSize().h;
    if (!options.force && !canPlace(x, y, w, h)) {
      hintEl.textContent = "Сюда не влезает — сдвинь кирпич.";
      return null;
    }

    const body = Bodies.rectangle(x, y, w, h, {
      friction: 1.15,
      frictionStatic: 3.2,
      restitution: 0,
      density: 0.0036,
      slop: 0.03,
      chamfer: { radius: 1 },
      angularDamping: 0.96,
      frictionAir: 0.002,
      collisionFilter: { category: CAT_BRICK, mask: MASK_SOLID },
      label: "brick",
      plugin: {
        kind: "brick",
        w,
        h,
        seed: (Math.random() * 10000) | 0,
        tone: 0.82 + Math.random() * 0.28,
        soot: { l: 0, r: 0, t: 0, b: 0 },
        heat: 0,
      },
    });
    Body.setInertia(body, body.inertia * 7);
    Body.setVelocity(body, { x: 0, y: 0 });
    Body.setAngularVelocity(body, 0);
    World.add(world, body);
    state.bricksList.push(body);
    burst(x, y, "#c35a3d", 8);
    if (!options.silent) {
      if (keys.has("Shift")) applyCementNear(body, true);
      refreshJoints();
    }
    return body;
  }

  function spawnSawdust(x, y) {
    const grains = [];
    const count = 42 + ((Math.random() * 16) | 0);
    for (let i = 0; i < count; i += 1) {
      const gx = x + (Math.random() - 0.5) * 18;
      const gy = y - 6 - Math.random() * 14;
      if (insideSolid(gx, gy)) continue;
      const r = 1.15 + Math.random() * 0.95;
      const body = Bodies.circle(gx, gy, r, {
        friction: 0.78,
        frictionStatic: 0.62,
        frictionAir: 0.003,
        restitution: 0.02,
        density: 0.00085,
        slop: 0.06,
        sleepThreshold: 28,
        collisionFilter: { category: CAT_FUEL, mask: MASK_SOLID },
        label: "sawdust",
        plugin: {
          kind: "sawdust",
          w: r * 2.2,
          h: r * 0.85,
          r,
          seed: (Math.random() * 10000) | 0,
          tone: 0.72 + Math.random() * 0.4,
          burning: false,
          fuel: 0.7 + Math.random() * 0.35,
        },
      });
      Body.setVelocity(body, { x: (Math.random() - 0.5) * 1.6, y: 0.4 + Math.random() * 1.4 });
      Body.setAngularVelocity(body, (Math.random() - 0.5) * 0.35);
      World.add(world, body);
      state.fuels.push(body);
      grains.push(body);
    }
    if (!grains.length) {
      hintEl.textContent = "Сюда не сыпется — внутри кирпича.";
      return [];
    }
    state.lastPour = state.time;
    burst(x, y, "#c9a36a", 8);
    hintEl.textContent = "Опилки сыплются. Кучка осыпается и течёт, как песок.";
    return grains;
  }

  function spawnPipe(x, y, options = {}) {
    if (!options.force && !canPlace(x, y, PIPE_W, PIPE_H)) {
      hintEl.textContent = "Труба не встаёт — подвинь.";
      return null;
    }
    const body = Bodies.rectangle(x, y, PIPE_W, PIPE_H, {
      friction: 0.95,
      frictionStatic: 2,
      restitution: 0,
      density: 0.004,
      frictionAir: 0.002,
      angularDamping: 0.97,
      collisionFilter: { category: CAT_FUEL, mask: MASK_SOLID },
      label: "pipe",
      plugin: { kind: "pipe", w: PIPE_W, h: PIPE_H },
    });
    Body.setInertia(body, body.inertia * 5);
    World.add(world, body);
    state.pipeList.push(body);
    if (!options.silent) {
      hintEl.textContent = "Труба стоит. Поддержи её подпоркой или цементом, иначе упадёт. Дым всосёт только с устья.";
    }
    return body;
  }

  function currentStove() {
    return STOVES[state.stoveId] || STOVES.russian;
  }

  function stoveBrickPos(origin, preset, col, row) {
    const offset = preset.running && row % 2 ? CELL_W / 2 : 0;
    return {
      x: origin.x + (col - preset.originCol) * CELL_W + offset,
      y: origin.y - row * CELL_H,
    };
  }

  function stovePipePos(origin, preset) {
    const below = stoveBrickPos(origin, preset, preset.pipe.col, preset.pipe.row - 1);
    return {
      x: below.x,
      y: below.y - BRICK_H / 2 - PIPE_H / 2 - 1,
    };
  }

  function stoveOriginAt(x, y) {
    return placePoint(x, y, BRICK_W, BRICK_H);
  }

  function stoveFits(origin, preset) {
    return (
      preset.bricks.every(([col, row]) => {
        const pos = stoveBrickPos(origin, preset, col, row);
        return canPlace(pos.x, pos.y, BRICK_W, BRICK_H);
      }) &&
      canPlace(stovePipePos(origin, preset).x, stovePipePos(origin, preset).y, PIPE_W, PIPE_H)
    );
  }

  function cementAllOpen() {
    refreshJoints();
    state.joints.forEach((joint) => {
      if (!joint.sealed) weld(joint);
    });
  }

  function placeStove(x, y) {
    const preset = currentStove();
    const origin = stoveOriginAt(x, y);
    if (!stoveFits(origin, preset)) {
      hintEl.textContent = "Печка сюда не встаёт — сдвинь или расчисти место.";
      return false;
    }
    preset.bricks.forEach(([col, row]) => {
      const pos = stoveBrickPos(origin, preset, col, row);
      spawnBrick(pos.x, pos.y, { w: BRICK_W, h: BRICK_H, force: true, silent: true });
    });
    const pipe = stovePipePos(origin, preset);
    spawnPipe(pipe.x, pipe.y, { force: true, silent: true });
    cementAllOpen();
    hintEl.textContent = `${preset.name} стоит. Можно сыпать опилки и зажигать.`;
    return true;
  }

  function propSize() {
    return state.rotated
      ? { w: PROP_LEN, h: PROP_THICK }
      : { w: PROP_THICK, h: PROP_LEN };
  }

  function spawnProp(x, y) {
    const { w, h } = propSize();
    if (!canPlace(x, y, w, h)) {
      hintEl.textContent = "Подпорка сюда не встаёт.";
      return null;
    }
    const body = Bodies.rectangle(x, y, w, h, {
      friction: 1,
      frictionStatic: 2.2,
      restitution: 0,
      density: 0.0018,
      frictionAir: 0.003,
      angularDamping: 0.9,
      collisionFilter: { category: CAT_PROP, mask: MASK_SOLID },
      label: "prop",
      plugin: {
        kind: "prop",
        w,
        h,
        seed: (Math.random() * 10000) | 0,
        burning: false,
        fuel: 2.4,
      },
    });
    Body.setInertia(body, body.inertia * 4);
    Body.setVelocity(body, { x: 0, y: 0 });
    World.add(world, body);
    state.props.push(body);
    hintEl.textContent = "Подпорка как пять кирпичей сбоку. Дерево горит.";
    return body;
  }

  function spawnMatch(x, y) {
    const body = Bodies.rectangle(x, y, 6, 28, {
      friction: 0.4,
      restitution: 0.1,
      density: 0.0006,
      collisionFilter: { category: CAT_FUEL, mask: MASK_SOLID },
      label: "match",
      plugin: { kind: "match", w: 6, h: 28, life: 1, tip: 1 },
    });
    Body.setAngularVelocity(body, (Math.random() - 0.5) * 0.12);
    World.add(world, body);
    state.matches.push(body);
    return body;
  }

  function pairKey(a, b) {
    return a.id < b.id ? `${a.id}:${b.id}` : `${b.id}:${a.id}`;
  }

  function jointGeometry(a, b) {
    const pipeJoint = a.plugin.kind === "pipe" || b.plugin.kind === "pipe";
    const gapLimit = pipeJoint ? 40 : JOINT_GAP;
    const nest = pipeJoint ? -28 : -12;
    const sepX = Math.max(a.bounds.min.x - b.bounds.max.x, b.bounds.min.x - a.bounds.max.x);
    const sepY = Math.max(a.bounds.min.y - b.bounds.max.y, b.bounds.min.y - a.bounds.max.y);
    const overlapX = Math.min(a.bounds.max.x, b.bounds.max.x) - Math.max(a.bounds.min.x, b.bounds.min.x);
    const overlapY = Math.min(a.bounds.max.y, b.bounds.max.y) - Math.max(a.bounds.min.y, b.bounds.min.y);
    const sideBySide = overlapY > 10 && sepX <= gapLimit && sepX > nest;
    const stacked = overlapX > 10 && sepY <= gapLimit && sepY > nest;

    if (sideBySide && (!stacked || overlapY >= overlapX)) {
      const x = (a.position.x < b.position.x ? a.bounds.max.x + b.bounds.min.x : b.bounds.max.x + a.bounds.min.x) / 2;
      const y1 = Math.max(a.bounds.min.y, b.bounds.min.y);
      const y2 = Math.min(a.bounds.max.y, b.bounds.max.y);
      return { axis: "h", gap: Math.max(0, sepX), x, y: (y1 + y2) / 2, length: y2 - y1 };
    }
    if (stacked) {
      const y = (a.position.y < b.position.y ? a.bounds.max.y + b.bounds.min.y : b.bounds.max.y + a.bounds.min.y) / 2;
      const x1 = Math.max(a.bounds.min.x, b.bounds.min.x);
      const x2 = Math.min(a.bounds.max.x, b.bounds.max.x);
      return { axis: "v", gap: Math.max(0, sepY), x: (x1 + x2) / 2, y, length: x2 - x1 };
    }
    return null;
  }

  function masonryBodies() {
    return [...state.bricksList, ...state.pipeList];
  }

  function findJoints() {
    const found = [];
    const list = masonryBodies();
    for (let i = 0; i < list.length; i += 1) {
      for (let j = i + 1; j < list.length; j += 1) {
        const a = list[i];
        const b = list[j];
        const geo = jointGeometry(a, b);
        if (!geo) continue;
        const key = pairKey(a, b);
        const existing = state.joints.find((item) => item.key === key);
        found.push({
          key,
          a,
          b,
          geo,
          sealed: Boolean(existing && existing.sealed),
          constraints: existing ? existing.constraints : [],
        });
      }
    }
    return found;
  }

  function refreshJoints() {
    const next = findJoints();
    const byKey = new Map(next.map((joint) => [joint.key, joint]));
    state.joints.forEach((old) => {
      if (!old.sealed) return;
      const fresh = byKey.get(old.key);
      if (fresh) {
        fresh.sealed = true;
        fresh.constraints = old.constraints;
      } else {
        byKey.set(old.key, old);
      }
    });
    state.joints = [...byKey.values()];
    updateSealUi();
  }

  function weld(joint) {
    if (joint.sealed) return false;
    const { a, b, geo } = joint;
    const ax = geo.x - a.position.x;
    const ay = geo.y - a.position.y;
    const bx = geo.x - b.position.x;
    const by = geo.y - b.position.y;
    const tangent = geo.axis === "h" ? { x: 0, y: Math.max(8, geo.length * 0.28) } : { x: Math.max(8, geo.length * 0.28), y: 0 };
    const make = (ox, oy) =>
      Constraint.create({
        bodyA: a,
        bodyB: b,
        pointA: { x: ax + ox, y: ay + oy },
        pointB: { x: bx + ox, y: by + oy },
        stiffness: 0.995,
        damping: 0.42,
        length: Math.max(1, geo.gap),
      });
    const constraints = [make(0, 0), make(tangent.x, tangent.y), make(-tangent.x, -tangent.y)];
    constraints.forEach((c) => World.add(world, c));
    joint.sealed = true;
    joint.constraints = constraints;
    const idx = state.joints.findIndex((item) => item.key === joint.key);
    if (idx >= 0) state.joints[idx] = joint;
    else state.joints.push(joint);
    burst(geo.x, geo.y, "#ddd0b4", 12);
    const pipeJoint = a.plugin.kind === "pipe" || b.plugin.kind === "pipe";
    hintEl.textContent = pipeJoint
      ? "Труба прихвачена цементом к кирпичу."
      : "Шов схвачен. Через кирпич дым не пройдёт.";
    updateSealUi();
    return true;
  }

  function applyCementNear(body, quiet) {
    refreshJoints();
    let used = 0;
    state.joints.forEach((joint) => {
      if ((joint.a === body || joint.b === body) && !joint.sealed && weld(joint)) used += 1;
    });
    if (!quiet && used === 0) hintEl.textContent = "Рядом нет открытого шва.";
  }

  function jointAt(x, y) {
    let best = null;
    let bestDist = 42;
    state.joints.forEach((joint) => {
      if (joint.sealed) return;
      const d = Math.hypot(joint.geo.x - x, joint.geo.y - y);
      if (d < bestDist) {
        best = joint;
        bestDist = d;
      }
    });
    return best;
  }

  function nearestPipeJoint(x, y) {
    let best = null;
    let bestDist = 56;
    state.joints.forEach((joint) => {
      if (joint.sealed) return;
      if (joint.a.plugin.kind !== "pipe" && joint.b.plugin.kind !== "pipe") return;
      const d = Math.hypot(joint.geo.x - x, joint.geo.y - y);
      if (d < bestDist) {
        best = joint;
        bestDist = d;
      }
    });
    return best;
  }

  function forceAttachPipe(x, y) {
    let pipe = null;
    let pipeDist = 72;
    state.pipeList.forEach((item) => {
      const d = Math.hypot(item.position.x - x, item.position.y - y);
      if (d < pipeDist) {
        pipe = item;
        pipeDist = d;
      }
    });
    if (!pipe) return false;
    let brick = null;
    let brickGap = 48;
    state.bricksList.forEach((item) => {
      const dx = Math.max(0, Math.max(item.bounds.min.x - pipe.bounds.max.x, pipe.bounds.min.x - item.bounds.max.x));
      const dy = Math.max(0, Math.max(item.bounds.min.y - pipe.bounds.max.y, pipe.bounds.min.y - item.bounds.max.y));
      const gap = Math.hypot(dx, dy);
      if (gap < brickGap) {
        brick = item;
        brickGap = gap;
      }
    });
    if (!brick) return false;
    const key = pairKey(pipe, brick);
    const existing = state.joints.find((joint) => joint.key === key);
    if (existing) {
      if (existing.sealed) return false;
      return weld(existing);
    }
    const geo = jointGeometry(pipe, brick) || {
      axis: "v",
      gap: Math.max(1, brickGap),
      x: (Math.max(pipe.bounds.min.x, brick.bounds.min.x) + Math.min(pipe.bounds.max.x, brick.bounds.max.x)) / 2,
      y: (pipe.position.y < brick.position.y ? pipe.bounds.max.y + brick.bounds.min.y : brick.bounds.max.y + pipe.bounds.min.y) / 2,
      length: 24,
    };
    return weld({ key, a: pipe, b: brick, geo, sealed: false, constraints: [] });
  }

  function removeBodyFrom(list, body) {
    const idx = list.indexOf(body);
    if (idx >= 0) list.splice(idx, 1);
    World.remove(world, body);
  }

  function dropIfFallen(body, list, refund) {
    if (body.position.y <= groundY + 500) return false;
    if (body.plugin.kind === "brick" || body.plugin.kind === "pipe") {
      state.joints.forEach((joint) => {
        if (joint.a === body || joint.b === body) joint.constraints.forEach((c) => World.remove(world, c));
      });
    }
    removeBodyFrom(list, body);
    refund();
    return true;
  }

  function reclaimFallen() {
    const brickBefore = state.bricksList.length;
    state.bricksList.slice().forEach((brick) => {
      dropIfFallen(brick, state.bricksList, () => {});
    });
    state.fuels.slice().forEach((fuel) => {
      dropIfFallen(fuel, state.fuels, () => {});
    });
    state.pipeList.slice().forEach((pipe) => {
      dropIfFallen(pipe, state.pipeList, () => {});
    });
    state.props.slice().forEach((prop) => {
      dropIfFallen(prop, state.props, () => {});
    });
    state.matches.slice().forEach((match) => {
      if (match.position.y > groundY + 500) removeBodyFrom(state.matches, match);
    });
    state.ashes.slice().forEach((ash) => {
      dropIfFallen(ash, state.ashes, () => {});
    });
    if (brickBefore !== state.bricksList.length) refreshJoints();
  }

  function sealRatio() {
    if (!state.joints.length) return 0;
    return state.joints.filter((j) => j.sealed).length / state.joints.length;
  }

  function updateSealUi() {
    const total = state.joints.length;
    const sealed = state.joints.filter((j) => j.sealed).length;
    jointValue.textContent = `${sealed} / ${total}`;
    if (!total) {
      sealFill.style.width = "0%";
      sealValue.textContent = "—";
      return;
    }
    const pct = Math.round((sealed / total) * 100);
    sealFill.style.width = `${pct}%`;
    sealValue.textContent = `${pct}%`;
  }

  function updateTempUi() {
    const shown = Math.round(state.temp);
    tempValue.textContent = `${shown}°`;
    tempFill.style.width = `${Math.min(100, (state.temp / 820) * 100)}%`;
  }

  function burst(x, y, color, count) {
    for (let i = 0; i < count; i += 1) {
      const ang = Math.random() * Math.PI * 2;
      const spd = 0.6 + Math.random() * 2.2;
      state.particles.push({
        x,
        y,
        vx: Math.cos(ang) * spd,
        vy: Math.sin(ang) * spd - 1.2,
        life: 1,
        color,
        size: 1.5 + Math.random() * 2.4,
      });
    }
  }

  function emitSmoke(x, y, force) {
    const n = force > 0.55 ? 5 : 3;
    for (let i = 0; i < n; i += 1) {
      state.smoke.push({
        x: x + (Math.random() - 0.5) * 10,
        y: y - 4 + (Math.random() - 0.5) * 6,
        vx: (Math.random() - 0.5) * 0.35,
        vy: -0.45 - Math.random() * 0.55,
        size: 10 + Math.random() * 16,
        dark: 0.55 + Math.random() * 0.35,
      });
    }
    if (state.smoke.length > 720) state.smoke.splice(0, state.smoke.length - 720);
  }

  function spawnAshAt(x, y, count) {
    for (let i = 0; i < count; i += 1) {
      let gx = x + (Math.random() - 0.5) * 12;
      let gy = y + 2 + Math.random() * 8;
      if (insideSolid(gx, gy)) gy = y + 12;
      const r = 0.85 + Math.random() * 1.35;
      const body = Bodies.circle(gx, gy, r, {
        friction: 0.88,
        frictionStatic: 0.75,
        frictionAir: 0.002,
        restitution: 0.015,
        density: 0.001,
        slop: 0.08,
        sleepThreshold: 16,
        collisionFilter: { category: CAT_FUEL, mask: MASK_SOLID },
        label: "ash",
        plugin: {
          kind: "ash",
          r,
          seed: (Math.random() * 10000) | 0,
          tone: 0.3 + Math.random() * 0.55,
        },
      });
      Body.setVelocity(body, { x: (Math.random() - 0.5) * 1.8, y: 1.2 + Math.random() * 3.4 });
      Body.setAngularVelocity(body, (Math.random() - 0.5) * 0.5);
      World.add(world, body);
      state.ashes.push(body);
    }
    if (state.ashes.length <= count) hintEl.textContent = "Зола сыплется крупинками и падает вниз.";
    while (state.ashes.length > ASH_CAP) removeBodyFrom(state.ashes, state.ashes[0]);
  }

  function clearAshes() {
    state.ashes.slice().forEach((ash) => removeBodyFrom(state.ashes, ash));
  }

  function fires() {
    return [
      ...state.fuels.filter((f) => f.plugin.burning && f.plugin.fuel > 0),
      ...state.props.filter((p) => p.plugin.burning && p.plugin.fuel > 0),
    ];
  }

  function nearBody(x, y, body, pad) {
    const b = body.bounds;
    return x > b.min.x - pad && x < b.max.x + pad && y > b.min.y - pad && y < b.max.y + pad;
  }

  function chimney() {
    return state.pipeList.length > 0;
  }

  function pointInBrick(x, y) {
    for (let i = 0; i < state.bricksList.length; i += 1) {
      const b = state.bricksList[i].bounds;
      if (x >= b.min.x && x <= b.max.x && y >= b.min.y && y <= b.max.y) return true;
    }
    return false;
  }

  function lineHitsBrick(x0, y0, x1, y1) {
    const dist = Math.hypot(x1 - x0, y1 - y0);
    const steps = Math.max(3, Math.ceil(dist / 5));
    for (let i = 1; i < steps; i += 1) {
      const t = i / steps;
      if (pointInBrick(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)) return true;
    }
    return false;
  }

  function pipeFlueAt(x, y) {
    for (let i = 0; i < state.pipeList.length; i += 1) {
      const pipe = state.pipeList[i];
      const b = pipe.bounds;
      const inset = 8;
      if (x > b.min.x + inset && x < b.max.x - inset && y >= b.min.y - 12 && y <= b.max.y + 10) {
        return pipe;
      }
    }
    return null;
  }

  function ejectFromBrick(p) {
    for (let i = 0; i < state.bricksList.length; i += 1) {
      const b = state.bricksList[i].bounds;
      if (p.x < b.min.x || p.x > b.max.x || p.y < b.min.y || p.y > b.max.y) continue;
      const left = p.x - b.min.x;
      const right = b.max.x - p.x;
      const top = p.y - b.min.y;
      const bottom = b.max.y - p.y;
      const m = Math.min(left, right, top, bottom);
      if (m === left) p.x = b.min.x - 1.5;
      else if (m === right) p.x = b.max.x + 1.5;
      else if (m === top) p.y = b.min.y - 1.5;
      else p.y = b.max.y + 1.5;
      return;
    }
  }

  function leakSmoke(p) {
    const leaks = state.joints.filter((j) => !j.sealed);
    leaks.forEach((joint) => {
      const d = Math.hypot(joint.geo.x - p.x, joint.geo.y - p.y);
      if (d > 26) return;
      const stove = stoveCenter();
      const ox = joint.geo.x - stove.x;
      const oy = joint.geo.y - stove.y;
      const len = Math.hypot(ox, oy) || 1;
      p.vx += (ox / len) * 0.12;
      p.vy += (oy / len) * 0.08;
    });
  }

  function stoveCenter() {
    if (!state.bricksList.length) return { x: originX, y: groundY - 80 };
    let x = 0;
    let y = 0;
    state.bricksList.forEach((b) => {
      x += b.position.x;
      y += b.position.y;
    });
    return { x: x / state.bricksList.length, y: y / state.bricksList.length };
  }

  function updateSmoke() {
    const sealed = sealRatio();
    const heat = Math.max(0, (state.temp - 20) / 800);
    state.smoke.forEach((p) => {
      const flue = pipeFlueAt(p.x, p.y);
      const speed = Math.max(0.32, Math.hypot(p.vx, p.vy));

      if (flue) {
        p.vx = (flue.position.x - p.x) * 0.2;
        p.vy = -speed;
      } else {
        p.vy -= 0.018 + heat * 0.03;
        p.vx += (Math.random() - 0.5) * 0.04;
        p.vy += (Math.random() - 0.5) * 0.012;

        let nearest = null;
        let nearestDist = 64;
        state.pipeList.forEach((pipe) => {
          const ix = pipe.position.x;
          const iy = pipe.bounds.max.y + 3;
          const d = Math.hypot(ix - p.x, iy - p.y);
          if (d < nearestDist && !lineHitsBrick(p.x, p.y, ix, iy)) {
            nearest = { x: ix, y: iy };
            nearestDist = d;
          }
        });
        if (nearest) {
          const dx = nearest.x - p.x;
          const dy = nearest.y - p.y;
          const dist = Math.hypot(dx, dy) || 1;
          p.vx = (dx / dist) * speed;
          p.vy = (dy / dist) * speed;
        }

        if (sealed < 0.85) leakSmoke(p);
      }

      let nx = p.x + p.vx;
      let ny = p.y + p.vy;
      if (!pipeFlueAt(nx, ny) && pointInBrick(nx, ny)) {
        const slideX = !pointInBrick(nx, p.y);
        const slideY = !pointInBrick(p.x, ny);
        if (slideX && !slideY) {
          ny = p.y;
          p.vy = Math.min(0, p.vy) - 0.06;
          p.vx *= 0.45;
        } else if (slideY && !slideX) {
          nx = p.x;
          p.vx *= -0.2;
        } else {
          if (pointInBrick(p.x, p.y)) ejectFromBrick(p);
          nx = p.x;
          ny = p.y;
          p.vx *= 0.25;
          p.vy = Math.min(p.vy, -0.05);
        }
      }

      p.x = nx;
      p.y = ny;
      if (p.size < 40) p.size += 0.025;
    });
    state.smoke = state.smoke.filter((p) => smokeOnScreen(p.x, p.y));
  }

  function smokeOnScreen(x, y) {
    const sx = (x - width / 2 - state.camera.x) * state.camera.zoom + width / 2;
    const sy = (y - height / 2 - state.camera.y) * state.camera.zoom + height / 2;
    return sx > -120 && sx < width + 120 && sy > -120 && sy < height + 120;
  }

  function igniteFuel(fuel) {
    if (!fuel || fuel.plugin.burning || fuel.plugin.fuel == null) return;
    const first = fires().length === 0;
    fuel.plugin.burning = true;
    burst(fuel.position.x, fuel.position.y, "#ffb347", 6);
    if (first) {
      hintEl.textContent = fuel.label === "prop"
        ? "Подпорка занялась. Дерево горит — скоро осыплется."
        : "Опилки занялись. Огонь ползёт по куче.";
    }
  }

  function flammables() {
    return [...state.fuels, ...state.props];
  }

  function tryIgniteAt(x, y, radius) {
    let lit = 0;
    flammables().forEach((fuel) => {
      if (nearBody(x, y, fuel, radius)) {
        igniteFuel(fuel);
        lit += 1;
      }
    });
    return lit > 0;
  }

  function spreadFire() {
    const burning = fires();
    burning.forEach((hot) => {
      flammables().forEach((other) => {
        if (other.plugin.burning) return;
        const pad = other.label === "prop" || hot.label === "prop" ? 16 : 13;
        if (nearBody(hot.position.x, hot.position.y, other, pad) || nearBody(other.position.x, other.position.y, hot, pad)) {
          if (Math.random() < 0.08) igniteFuel(other);
        }
      });
    });
  }

  function updateFire() {
    const burning = fires();
    if (state.time % 4 === 0) spreadFire();
    burning.forEach((fuel) => {
      fuel.plugin.fuel -= fuel.label === "prop" ? 0.0011 : 0.0024;
      const pos = fuel.position;
      if (fuel.label === "prop") {
        const along = Math.max(fuel.plugin.w, fuel.plugin.h);
        const t = Math.random() - 0.5;
        const c = Math.cos(fuel.angle);
        const s = Math.sin(fuel.angle);
        const lx = fuel.plugin.w >= fuel.plugin.h ? t * along : 0;
        const ly = fuel.plugin.h > fuel.plugin.w ? t * along : 0;
        const sx = pos.x + lx * c - ly * s;
        const sy = pos.y + lx * s + ly * c;
        if (Math.random() < 0.28) emitSmoke(sx, sy - 6, fuel.plugin.fuel);
        if (Math.random() < 0.1) burst(sx, sy - 4, Math.random() > 0.5 ? "#ffb347" : "#ff6a2a", 1);
        if (Math.random() < 0.22) spawnAshAt(sx, sy + 4, 2);
      } else {
        if (Math.random() < 0.12) emitSmoke(pos.x, pos.y - 4, fuel.plugin.fuel);
        if (Math.random() < 0.08) {
          burst(pos.x + (Math.random() - 0.5) * 6, pos.y - 3, Math.random() > 0.5 ? "#ffb347" : "#ff6a2a", 1);
        }
        if (Math.random() < 0.1) spawnAshAt(pos.x, pos.y + 3, 1);
      }
      if (fuel.plugin.fuel <= 0) {
        if (fuel.label === "prop") {
          spawnAshAt(pos.x, pos.y + 6, 28);
          removeBodyFrom(state.props, fuel);
        } else {
          spawnAshAt(pos.x, pos.y + 3, 6);
          removeBodyFrom(state.fuels, fuel);
        }
      }
    });

    const firePower = Math.min(3.4, burning.length * 0.05);
    const leak = 1 - sealRatio();
    const draft = chimney() ? 0.04 : 0;
    state.temp += firePower * 0.7;
    state.temp -= 0.05 + leak * 0.16 + draft;
    if (firePower <= 0) state.temp -= (state.temp - 20) * 0.008;
    state.temp = Math.max(20, Math.min(860, state.temp));
    updateTempUi();

    const heatNorm = Math.max(0, (state.temp - 40) / 700);
    state.bricksList.forEach((brick) => {
      brick.plugin.heat += (heatNear(brick) - brick.plugin.heat) * 0.03;
      brick.plugin.heat = Math.max(0, Math.min(1, brick.plugin.heat));
      burning.forEach((fuel) => stainBrick(brick, fuel.position.x, fuel.position.y, 0.0035 * (0.4 + heatNorm)));
    });
  }

  function heatNear(brick) {
    let best = 0;
    fires().forEach((fuel) => {
      const d = Math.hypot(fuel.position.x - brick.position.x, fuel.position.y - brick.position.y);
      best = Math.max(best, Math.max(0, 1 - d / 160));
    });
    return best;
  }

  function stainBrick(brick, fx, fy, amount) {
    const dx = fx - brick.position.x;
    const dy = fy - brick.position.y;
    const dist = Math.hypot(dx, dy);
    if (dist > 150) return;
    const c = Math.cos(-brick.angle);
    const s = Math.sin(-brick.angle);
    const lx = dx * c - dy * s;
    const ly = dx * s + dy * c;
    const add = amount * (1 - dist / 150);
    const soot = brick.plugin.soot;
    if (Math.abs(lx) > Math.abs(ly)) {
      if (lx < 0) soot.l = Math.min(1, soot.l + add);
      else soot.r = Math.min(1, soot.r + add);
    } else if (ly < 0) soot.t = Math.min(1, soot.t + add);
    else soot.b = Math.min(1, soot.b + add);
  }

  function updateMatches() {
    state.matches.slice().forEach((match) => {
      match.plugin.life -= 0.004;
      const tipX = match.position.x - Math.sin(match.angle) * 12;
      const tipY = match.position.y - Math.cos(match.angle) * 12;
      tryIgniteAt(tipX, tipY, 22);
      if (Math.random() < 0.4) emitSmoke(tipX, tipY, 0.3);
      if (match.plugin.life <= 0) removeBodyFrom(state.matches, match);
    });
  }

  function cleanStove() {
    state.bricksList.forEach((brick) => {
      brick.plugin.soot = { l: 0, r: 0, t: 0, b: 0 };
    });
    clearAshes();
    state.smoke = [];
    hintEl.textContent = "Сажу сняли, золу выгребли. Кирпичи на месте.";
  }

  function deleteStove() {
    [...state.bricksList, ...state.fuels, ...state.pipeList, ...state.props, ...state.matches, ...state.ashes].forEach((body) => {
      World.remove(world, body);
    });
    state.joints.forEach((joint) => joint.constraints.forEach((c) => World.remove(world, c)));
    state.bricksList = [];
    state.fuels = [];
    state.pipeList = [];
    state.props = [];
    state.matches = [];
    state.joints = [];
    state.ashes = [];
    state.smoke = [];
    state.particles = [];
    state.temp = 20;
    updateSealUi();
    updateTempUi();
    hintEl.textContent = "Печку разобрали. Можно класть заново.";
  }

  function worldPoint(clientX, clientY) {
    const rect = canvas.getBoundingClientRect();
    return {
      x: (clientX - rect.left - width / 2) / state.camera.zoom + width / 2 + state.camera.x,
      y: (clientY - rect.top - height / 2) / state.camera.zoom + height / 2 + state.camera.y,
    };
  }

  function screenToWorld(e) {
    return worldPoint(e.clientX, e.clientY);
  }

  const keys = new Set();

  function onPointerMove(e) {
    state.pointer = { ...state.pointer, ...screenToWorld(e) };
    if (state.tool === TOOL.CEMENT) {
      refreshJoints();
      state.hoverJoint = jointAt(state.pointer.x, state.pointer.y);
    } else {
      state.hoverJoint = null;
    }
  }

  function onPointerDown(e) {
    if (!state.started) return;
    if (e.button !== 0) return;
    if (e.target.closest(".toolbar, .topbar, .overlay, .hint, .actions, .catalog")) return;
    state.pointer.down = true;
    const p = screenToWorld(e);
    state.pointer.x = p.x;
    state.pointer.y = p.y;

    if (state.tool === TOOL.STOVE) {
      placeStove(p.x, p.y);
    } else if (state.tool === TOOL.BRICK) {
      const { w, h } = brickSize();
      const at = placePoint(p.x, p.y, w, h);
      spawnBrick(at.x, at.y);
    } else if (state.tool === TOOL.CEMENT) {
      refreshJoints();
      const joint = jointAt(p.x, p.y) || nearestPipeJoint(p.x, p.y);
      if (joint) weld(joint);
      else if (!forceAttachPipe(p.x, p.y)) hintEl.textContent = "Цемент мажется на шов кирпичей или на стык трубы с кладкой.";
    } else if (state.tool === TOOL.SAWDUST) {
      spawnSawdust(p.x, p.y);
    } else if (state.tool === TOOL.PIPE) {
      const at = placePoint(p.x, p.y, PIPE_W, PIPE_H);
      spawnPipe(at.x, at.y);
    } else if (state.tool === TOOL.PROP) {
      const { w, h } = propSize();
      const at = placePoint(p.x, p.y, w, h);
      spawnProp(at.x, at.y);
    } else if (state.tool === TOOL.MATCH) {
      if (!tryIgniteAt(p.x, p.y, 36)) spawnMatch(p.x, p.y);
    }
  }

  function onPointerUp() {
    state.pointer.down = false;
  }

  function offscreen(w, h) {
    const c = document.createElement("canvas");
    c.width = Math.max(2, Math.ceil(w));
    c.height = Math.max(2, Math.ceil(h));
    return c;
  }

  function brickTex(seed, w, h, tone) {
    const key = `b3:${seed}:${w | 0}:${h | 0}:${tone.toFixed(2)}`;
    if (texCache.has(key)) return texCache.get(key);
    const sx = 3;
    const c = offscreen(w * sx, h * sx);
    const g = c.getContext("2d");
    g.scale(sx, sx);
    const rnd = hash(seed);
    const hue = 6 + rnd() * 10;
    const grd = g.createLinearGradient(0, 0, w * 0.15, h);
    grd.addColorStop(0, `hsl(${hue + 8}, 54%, ${42 * tone}%)`);
    grd.addColorStop(0.4, `hsl(${hue + 3}, 50%, ${32 * tone}%)`);
    grd.addColorStop(1, `hsl(${hue}, 48%, ${20 * tone}%)`);
    g.fillStyle = grd;
    g.fillRect(0, 0, w, h);
    for (let i = 0; i < 220; i += 1) {
      g.fillStyle = rnd() > 0.52 ? `rgba(28,8,6,${0.05 + rnd() * 0.2})` : `rgba(255,214,176,${0.03 + rnd() * 0.14})`;
      g.fillRect(rnd() * w, rnd() * h, 0.6 + rnd() * 2.2, 0.5 + rnd() * 1.3);
    }
    g.strokeStyle = "rgba(18,6,4,0.22)";
    g.lineWidth = 0.55;
    for (let i = 0; i < 5; i += 1) {
      g.beginPath();
      g.moveTo(3 + rnd() * (w - 6), 3 + rnd() * (h - 6));
      g.quadraticCurveTo(w * rnd(), h * rnd(), 4 + rnd() * (w - 8), 4 + rnd() * (h - 8));
      g.stroke();
    }
    const chipX = 4 + rnd() * (w - 10);
    const chipY = 3 + rnd() * (h - 8);
    g.fillStyle = "rgba(0,0,0,0.18)";
    g.beginPath();
    g.moveTo(chipX, chipY);
    g.lineTo(chipX + 5 + rnd() * 4, chipY + 1);
    g.lineTo(chipX + 2, chipY + 3);
    g.fill();
    const lip = g.createLinearGradient(0, 0, 0, 8);
    lip.addColorStop(0, "rgba(255,226,196,0.42)");
    lip.addColorStop(1, "rgba(255,220,190,0)");
    g.fillStyle = lip;
    g.fillRect(1.5, 0.8, w - 3, 8);
    const shade = g.createLinearGradient(0, h - 9, 0, h);
    shade.addColorStop(0, "rgba(0,0,0,0)");
    shade.addColorStop(1, "rgba(0,0,0,0.42)");
    g.fillStyle = shade;
    g.fillRect(0, h - 9, w, 9);
    const side = g.createLinearGradient(0, 0, 7, 0);
    side.addColorStop(0, "rgba(0,0,0,0.32)");
    side.addColorStop(1, "rgba(0,0,0,0)");
    g.fillStyle = side;
    g.fillRect(0, 0, 7, h);
    const rim = g.createLinearGradient(w, 0, w - 6, 0);
    rim.addColorStop(0, "rgba(255,210,170,0.12)");
    rim.addColorStop(1, "rgba(255,210,170,0)");
    g.fillStyle = rim;
    g.fillRect(w - 6, 0, 6, h);
    texCache.set(key, c);
    return c;
  }

  function woodTex(seed, w, h) {
    const key = `w:${seed}:${w | 0}:${h | 0}`;
    if (texCache.has(key)) return texCache.get(key);
    const c = offscreen(w, h);
    const g = c.getContext("2d");
    const rnd = hash(seed);
    const along = w >= h;
    const grd = along ? g.createLinearGradient(0, 0, 0, h) : g.createLinearGradient(0, 0, w, 0);
    grd.addColorStop(0, "#4a2e16");
    grd.addColorStop(0.45, "#c4a06a");
    grd.addColorStop(1, "#3d2412");
    g.fillStyle = grd;
    g.fillRect(0, 0, w, h);
    g.strokeStyle = "rgba(60, 32, 12, 0.35)";
    g.lineWidth = 0.8;
    const lines = along ? 14 : 10;
    for (let i = 0; i < lines; i += 1) {
      g.beginPath();
      if (along) {
        const y = 2 + (i / lines) * (h - 4) + rnd() * 1.5;
        g.moveTo(1, y);
        g.bezierCurveTo(w * 0.33, y + rnd() * 3 - 1, w * 0.66, y + rnd() * 3 - 1, w - 1, y + rnd() * 2);
      } else {
        const x = 2 + (i / lines) * (w - 4) + rnd() * 1.5;
        g.moveTo(x, 1);
        g.bezierCurveTo(x + rnd() * 3 - 1, h * 0.33, x + rnd() * 3 - 1, h * 0.66, x + rnd() * 2, h - 1);
      }
      g.stroke();
    }
    if (rnd() > 0.35) {
      const kx = 6 + rnd() * (w - 12);
      const ky = 6 + rnd() * (h - 12);
      const knot = g.createRadialGradient(kx, ky, 0.5, kx, ky, 4 + rnd() * 3);
      knot.addColorStop(0, "#2a160c");
      knot.addColorStop(0.7, "#6a4220");
      knot.addColorStop(1, "rgba(80,48,20,0)");
      g.fillStyle = knot;
      g.beginPath();
      g.ellipse(kx, ky, 3.2, 2.2, rnd(), 0, Math.PI * 2);
      g.fill();
    }
    texCache.set(key, c);
    return c;
  }

  function shadeBody(body, x, y, w, h) {
    const glow = stoveGlow();
    let fire = 0;
    if (glow) {
      const d = Math.hypot(body.position.x - glow.x, body.position.y - glow.y);
      fire = Math.max(0, 1 - d / 250) * fireLight();
    }
    const win = Math.max(0, 0.28 - Math.abs(body.position.x - (originX - 170)) / 820);
    ctx.fillStyle = `rgba(6, 3, 2, ${Math.max(0, 0.24 - fire * 0.16 - win * 0.1)})`;
    ctx.fillRect(x, y, w, h);
    if (fire > 0.03) {
      const fg = ctx.createRadialGradient(0, h * 0.2, 2, 0, 0, Math.max(w, h));
      fg.addColorStop(0, `rgba(255, 120, 35, ${fire * 0.26})`);
      fg.addColorStop(1, "rgba(255, 80, 10, 0)");
      ctx.fillStyle = fg;
      ctx.fillRect(x, y, w, h);
    }
    if (win > 0.04) {
      const wg = ctx.createLinearGradient(x, y, x + w * 0.7, y + h * 0.2);
      wg.addColorStop(0, `rgba(255, 224, 176, ${win * 0.18})`);
      wg.addColorStop(1, "rgba(255, 224, 176, 0)");
      ctx.fillStyle = wg;
      ctx.fillRect(x, y, w, h);
    }
  }

  function buildRoom() {
    const c = offscreen(width, height);
    const g = c.getContext("2d");
    const wall = g.createLinearGradient(0, 0, 0, height);
    wall.addColorStop(0, "#4a382c");
    wall.addColorStop(0.45, "#2e221a");
    wall.addColorStop(1, "#16100c");
    g.fillStyle = wall;
    g.fillRect(0, 0, width, height);
    const rnd = hash(77);
    for (let i = 0; i < 1400; i += 1) {
      g.fillStyle = rnd() > 0.5 ? "rgba(20,12,8,0.08)" : "rgba(255,220,180,0.04)";
      g.fillRect(rnd() * width, rnd() * height, 1 + rnd() * 3, 1 + rnd() * 2);
    }
    g.fillStyle = "rgba(70, 52, 38, 0.28)";
    for (let y = 64; y < groundY; y += 18) g.fillRect(0, y, width, 1);
    g.fillStyle = "#2a1c14";
    g.fillRect(0, 48, width, 18);
    g.fillRect(0, groundY - 8, width, 10);
    const wx = width * 0.15;
    const wy = 78;
    g.fillStyle = "#3d2a1c";
    g.fillRect(wx - 86, wy - 18, 188, 128);
    const glass = g.createLinearGradient(wx - 74, wy - 6, wx + 86, wy + 96);
    glass.addColorStop(0, "#8ab0c8");
    glass.addColorStop(0.45, "#dce8f0");
    glass.addColorStop(1, "#6a8898");
    g.fillStyle = glass;
    g.fillRect(wx - 74, wy - 6, 164, 104);
    g.strokeStyle = "#2a1c14";
    g.lineWidth = 6;
    g.strokeRect(wx - 74, wy - 6, 164, 104);
    g.beginPath();
    g.moveTo(wx + 8, wy - 6);
    g.lineTo(wx + 8, wy + 98);
    g.moveTo(wx - 74, wy + 46);
    g.lineTo(wx + 90, wy + 46);
    g.stroke();
    g.fillStyle = "rgba(255,255,255,0.18)";
    g.fillRect(wx - 68, wy, 28, 36);
    g.fillStyle = "#1c120c";
    g.fillRect(originX + 280, 120, 14, groundY - 128);
    g.fillRect(originX + 250, 168, 74, 10);
    g.fillStyle = "#3a2818";
    g.fillRect(originX + 258, 186, 18, 46);
    g.fillRect(originX + 286, 186, 18, 38);
    const floor = g.createLinearGradient(0, groundY + 8, 0, height);
    floor.addColorStop(0, "#7a5640");
    floor.addColorStop(0.4, "#4a3224");
    floor.addColorStop(1, "#1a100c");
    g.fillStyle = floor;
    g.fillRect(0, groundY + 10, width, height - groundY);
    for (let x = 0, i = 0; x < width; x += 42, i += 1) {
      g.fillStyle = i % 2 ? "rgba(18, 10, 6, 0.28)" : "rgba(255, 200, 140, 0.05)";
      g.fillRect(x, groundY + 10, 40, height - groundY);
      g.strokeStyle = "rgba(12, 6, 4, 0.4)";
      g.beginPath();
      g.moveTo(x + 40, groundY + 10);
      g.lineTo(x + 40, height);
      g.stroke();
    }
    g.fillStyle = "rgba(0,0,0,0.4)";
    g.fillRect(0, groundY + 26, width, 12);
    return c;
  }

  function fireLight() {
    return Math.max(0, Math.min(1, (state.temp - 40) / 720));
  }

  function stoveGlow() {
    const burning = fires();
    if (!burning.length) return null;
    let x = 0;
    let y = 0;
    burning.forEach((b) => {
      x += b.position.x;
      y += b.position.y;
    });
    return { x: x / burning.length, y: y / burning.length, n: burning.length };
  }

  function drawContactShadow(body) {
    const b = body.bounds;
    const w = b.max.x - b.min.x;
    const h = b.max.y - b.min.y;
    const x = (b.min.x + b.max.x) / 2;
    const y = b.max.y + 1;
    ctx.save();
    ctx.globalAlpha = 0.34;
    const grd = ctx.createRadialGradient(x, y, 1, x, y + 2, Math.max(10, w * 0.58));
    grd.addColorStop(0, "rgba(0,0,0,0.55)");
    grd.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = grd;
    ctx.beginPath();
    ctx.ellipse(x, y, w * 0.5, Math.max(3.5, Math.min(10, h * 0.18)), 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  function drawShadows() {
    [...state.bricksList, ...state.pipeList, ...state.props, ...state.fuels, ...state.ashes].forEach(drawContactShadow);
  }

  function drawBackground() {
    if (!roomCanvas) roomCanvas = buildRoom();
    ctx.drawImage(roomCanvas, 0, 0, width, height);
    const heat = fireLight();
    const windowX = width * 0.15;
    const windowY = 78;
    ctx.save();
    ctx.globalAlpha = 0.2 + heat * 0.1;
    const shaft = ctx.createLinearGradient(windowX, windowY, windowX + 90, groundY);
    shaft.addColorStop(0, "rgba(255, 228, 176, 0.7)");
    shaft.addColorStop(1, "rgba(255, 180, 90, 0)");
    ctx.fillStyle = shaft;
    ctx.beginPath();
    ctx.moveTo(windowX - 70, windowY + 8);
    ctx.lineTo(windowX + 86, windowY + 8);
    ctx.lineTo(windowX + 280, groundY + 8);
    ctx.lineTo(windowX - 20, groundY + 16);
    ctx.closePath();
    ctx.fill();
    ctx.restore();

    if (heat > 0.02) {
      const glow = stoveGlow();
      const gx = glow ? (glow.x - state.camera.x - width / 2) * state.camera.zoom + width / 2 : originX;
      const gy = glow ? (glow.y - state.camera.y - height / 2) * state.camera.zoom + height / 2 : groundY - 80;
      const fire = ctx.createRadialGradient(gx, gy, 16, gx, gy, 460);
      fire.addColorStop(0, `rgba(255, 130, 40, ${0.1 + heat * 0.26})`);
      fire.addColorStop(0.4, `rgba(255, 70, 16, ${0.05 + heat * 0.12})`);
      fire.addColorStop(1, "rgba(255, 40, 0, 0)");
      ctx.fillStyle = fire;
      ctx.fillRect(0, 0, width, height);
    }

    for (let i = 0; i < 26; i += 1) {
      const px = ((i * 137 + state.time * 0.18) % (width + 40)) - 20;
      const py = 90 + ((i * 89 + state.time * 0.05) % (groundY - 140));
      ctx.fillStyle = `rgba(255, 232, 196, ${0.035 + (i % 5) * 0.012})`;
      ctx.beginPath();
      ctx.arc(px, py, 1.15, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function drawColorGrade() {
    const heat = fireLight();
    ctx.save();
    ctx.globalCompositeOperation = "soft-light";
    const grade = ctx.createLinearGradient(0, 0, 0, height);
    grade.addColorStop(0, "rgba(90, 70, 48, 0.28)");
    grade.addColorStop(0.55, "rgba(40, 24, 16, 0.12)");
    grade.addColorStop(1, "rgba(12, 6, 4, 0.38)");
    ctx.fillStyle = grade;
    ctx.fillRect(0, 0, width, height);
    ctx.restore();
    if (heat > 0.05) {
      const glow = stoveGlow();
      const gx = glow ? (glow.x - state.camera.x - width / 2) * state.camera.zoom + width / 2 : originX;
      const gy = glow ? (glow.y - state.camera.y - height / 2) * state.camera.zoom + height / 2 : groundY - 80;
      ctx.save();
      ctx.globalCompositeOperation = "lighter";
      const bloom = ctx.createRadialGradient(gx, gy, 8, gx, gy, 220);
      bloom.addColorStop(0, `rgba(255, 160, 60, ${0.08 + heat * 0.16})`);
      bloom.addColorStop(1, "rgba(255, 40, 0, 0)");
      ctx.fillStyle = bloom;
      ctx.fillRect(0, 0, width, height);
      ctx.restore();
    }
  }

  function drawFoundation() {
    const x = foundation.position.x;
    const y = foundation.position.y;
    const w = FOUNDATION_W;
    const h = 28;
    ctx.save();
    ctx.shadowColor = "rgba(0,0,0,0.45)";
    ctx.shadowBlur = 18;
    ctx.shadowOffsetY = 6;
    const grd = ctx.createLinearGradient(0, y - h / 2, 0, y + h / 2);
    grd.addColorStop(0, "#a8a094");
    grd.addColorStop(0.4, "#7a7368");
    grd.addColorStop(1, "#4a443c");
    ctx.fillStyle = grd;
    ctx.fillRect(x - w / 2, y - h / 2, w, h);
    ctx.shadowColor = "transparent";
    ctx.strokeStyle = "rgba(0,0,0,0.4)";
    ctx.strokeRect(x - w / 2, y - h / 2, w, h);
    ctx.fillStyle = "rgba(255,255,240,0.16)";
    ctx.fillRect(x - w / 2 + 3, y - h / 2 + 2, w - 6, 4);
    const rnd = hash(11);
    for (let i = 0; i < 40; i += 1) {
      ctx.fillStyle = rnd() > 0.5 ? "rgba(0,0,0,0.16)" : "rgba(255,255,230,0.1)";
      ctx.fillRect(x - w / 2 + rnd() * w, y - h / 2 + rnd() * h, 2 + rnd() * 4, 1.2);
    }
    ctx.restore();
  }

  function drawBrickBody(body) {
    const { w, h, seed, tone, soot, heat } = body.plugin;
    ctx.save();
    ctx.translate(body.position.x, body.position.y);
    ctx.rotate(body.angle);
    const x = -w / 2;
    const y = -h / 2;
    ctx.drawImage(brickTex(seed, w, h, tone), x, y, w, h);
    shadeBody(body, x, y, w, h);
    if (heat > 0.04) {
      ctx.fillStyle = `rgba(255, 90, 20, ${heat * 0.22})`;
      ctx.fillRect(x, y, w, h);
    }
    const stain = (from, to, alpha, vertical) => {
      if (alpha < 0.02) return;
      const g = vertical ? ctx.createLinearGradient(0, from, 0, to) : ctx.createLinearGradient(from, 0, to, 0);
      g.addColorStop(0, `rgba(8, 6, 5, ${Math.min(0.86, alpha)})`);
      g.addColorStop(1, "rgba(8, 6, 5, 0)");
      ctx.fillStyle = g;
      ctx.fillRect(x, y, w, h);
    };
    stain(x, x + w * 0.55, soot.l, false);
    stain(x + w, x + w * 0.45, soot.r, false);
    stain(y, y + h * 0.55, soot.t, true);
    stain(y + h, y + h * 0.45, soot.b, true);
    ctx.strokeStyle = "rgba(28, 10, 8, 0.55)";
    ctx.lineWidth = 1.2;
    roundRect(ctx, x, y, w, h, 2.5);
    ctx.stroke();
    ctx.restore();
  }

  function drawJoints() {
    state.joints.forEach((joint) => {
      const { geo, sealed } = joint;
      const hover = state.hoverJoint && state.hoverJoint.key === joint.key;
      ctx.save();
      ctx.translate(geo.x, geo.y);
      if (geo.axis === "h") ctx.rotate(Math.PI / 2);
      const len = Math.max(12, geo.length - 4);
      const thick = sealed ? 6.5 : hover ? 5 : 3;
      const mortar = ctx.createLinearGradient(0, -thick / 2, 0, thick / 2);
      if (sealed) {
        mortar.addColorStop(0, "#efe4c8");
        mortar.addColorStop(0.45, "#d4c3a0");
        mortar.addColorStop(1, "#9d8c6c");
      } else if (hover) {
        mortar.addColorStop(0, "#fff1c8");
        mortar.addColorStop(1, "#e0c88a");
      } else {
        mortar.addColorStop(0, "rgba(20, 12, 8, 0.35)");
        mortar.addColorStop(1, "rgba(10, 6, 4, 0.62)");
      }
      ctx.fillStyle = mortar;
      roundRect(ctx, -len / 2, -thick / 2, len, thick, 2);
      ctx.fill();
      if (sealed) {
        ctx.fillStyle = "rgba(255, 250, 230, 0.28)";
        ctx.fillRect(-len / 2 + 2, -thick / 2 + 1, len - 4, 2);
      }
      ctx.restore();
    });
  }

  function drawSawdust(body) {
    const { burning, fuel, w, h, tone } = body.plugin;
    ctx.save();
    ctx.translate(body.position.x, body.position.y);
    ctx.rotate(body.angle);
    if (burning) {
      ctx.globalCompositeOperation = "lighter";
      const glow = ctx.createRadialGradient(0, 0, 0.4, 0, 0, 8);
      glow.addColorStop(0, `rgba(255, 190, 70, ${0.35 + fuel * 0.25})`);
      glow.addColorStop(1, "rgba(255, 60, 0, 0)");
      ctx.fillStyle = glow;
      ctx.beginPath();
      ctx.arc(0, 0, 8, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalCompositeOperation = "source-over";
    }
    const chip = ctx.createLinearGradient(-w / 2, 0, w / 2, 0);
    chip.addColorStop(0, burning ? `hsl(18, 40%, ${10 + fuel * 8}%)` : `hsl(32, 38%, ${34 + tone * 10}%)`);
    chip.addColorStop(0.5, burning ? `hsl(22, 50%, ${18 + fuel * 10}%)` : `hsl(36, ${48 + tone * 12}%, ${50 + tone * 12}%)`);
    chip.addColorStop(1, burning ? `hsl(16, 36%, ${8 + fuel * 6}%)` : `hsl(28, 34%, ${28 + tone * 8}%)`);
    ctx.fillStyle = chip;
    roundRect(ctx, -w / 2, -h / 2, w, h, 1.2);
    ctx.fill();
    ctx.fillStyle = burning ? "rgba(255, 160, 60, 0.3)" : "rgba(255, 236, 190, 0.32)";
    ctx.fillRect(-w / 2 + 0.4, -h / 2 + 0.3, w - 0.8, 0.9);
    ctx.restore();
  }

  function drawPipe(body) {
    ctx.save();
    ctx.translate(body.position.x, body.position.y);
    ctx.rotate(body.angle);
    const x = -PIPE_W / 2;
    const y = -PIPE_H / 2;
    const metal = ctx.createLinearGradient(x, 0, x + PIPE_W, 0);
    metal.addColorStop(0, "#2c3034");
    metal.addColorStop(0.22, "#6d757c");
    metal.addColorStop(0.48, "#e4eaef");
    metal.addColorStop(0.62, "#8b939a");
    metal.addColorStop(1, "#2a2e32");
    ctx.fillStyle = metal;
    roundRect(ctx, x, y, PIPE_W, PIPE_H, 4);
    ctx.fill();
    shadeBody(body, x, y, PIPE_W, PIPE_H);
    ctx.fillStyle = "rgba(90, 40, 18, 0.18)";
    ctx.fillRect(x + 2, y + 18, 4, PIPE_H - 36);
    const hole = ctx.createLinearGradient(x + 8, 0, x + PIPE_W - 8, 0);
    hole.addColorStop(0, "#0a0b0c");
    hole.addColorStop(0.5, "#2a1a12");
    hole.addColorStop(1, "#050607");
    ctx.fillStyle = hole;
    ctx.fillRect(x + 7, y - 2, PIPE_W - 14, PIPE_H + 4);
    ctx.fillStyle = "rgba(0,0,0,0.45)";
    ctx.fillRect(x + 2, y + 10, PIPE_W - 4, 3);
    ctx.fillRect(x + 2, y + PIPE_H - 16, PIPE_W - 4, 3);
    ctx.fillStyle = "rgba(255,255,255,0.18)";
    ctx.fillRect(x + 5, y + 6, 2, PIPE_H - 14);
    ctx.restore();
  }

  function drawProp(body) {
    const { w, h, seed, burning, fuel } = body.plugin;
    ctx.save();
    ctx.translate(body.position.x, body.position.y);
    ctx.rotate(body.angle);
    const x = -w / 2;
    const y = -h / 2;
    if (burning) {
      ctx.globalCompositeOperation = "lighter";
      const glow = ctx.createRadialGradient(0, 0, 6, 0, 0, Math.max(w, h) * 0.45);
      glow.addColorStop(0, `rgba(255, 150, 50, ${0.22 + fuel * 0.14})`);
      glow.addColorStop(1, "rgba(255, 50, 0, 0)");
      ctx.fillStyle = glow;
      ctx.beginPath();
      ctx.arc(0, 0, Math.max(w, h) * 0.4, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalCompositeOperation = "source-over";
    }
    ctx.save();
    roundRect(ctx, x, y, w, h, 2);
    ctx.clip();
    ctx.drawImage(woodTex(seed, w, h), x, y, w, h);
    shadeBody(body, x, y, w, h);
    if (burning) {
      ctx.fillStyle = `rgba(40, 12, 4, ${0.35 + (1 - fuel) * 0.35})`;
      ctx.fillRect(x, y, w, h);
    }
    ctx.restore();
    ctx.strokeStyle = "rgba(30, 16, 8, 0.55)";
    ctx.lineWidth = 1.1;
    roundRect(ctx, x, y, w, h, 2);
    ctx.stroke();
    ctx.restore();
  }

  function drawAshes() {
    state.ashes.forEach((ash) => {
      const { seed, r, tone } = ash.plugin;
      const rnd = hash(seed);
      ctx.save();
      ctx.translate(ash.position.x, ash.position.y);
      ctx.rotate(ash.angle);
      ctx.fillStyle = `hsl(28, 7%, ${16 + tone * 30}%)`;
      ctx.beginPath();
      ctx.ellipse(0, 0, r * 1.35, r * 0.72, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = rnd() > 0.45 ? "rgba(220, 214, 204, 0.5)" : "rgba(28, 26, 24, 0.45)";
      ctx.fillRect(-r * 0.45, -r * 0.22, r * 0.7, r * 0.38);
      ctx.restore();
    });
  }

  function drawFlame(x, y, scale) {
    const t = state.time;
    const wobble = Math.sin(t * 0.28) * 2.4;
    const lift = Math.sin(t * 0.41) * 1.6;
    ctx.save();
    ctx.translate(x + wobble * 0.35, y + lift * 0.2);
    ctx.scale(scale, scale);
    ctx.globalCompositeOperation = "lighter";
    const bloom = ctx.createRadialGradient(0, 2, 1, 0, -4, 26);
    bloom.addColorStop(0, "rgba(255, 170, 60, 0.35)");
    bloom.addColorStop(1, "rgba(255, 40, 0, 0)");
    ctx.fillStyle = bloom;
    ctx.beginPath();
    ctx.arc(0, 0, 26, 0, Math.PI * 2);
    ctx.fill();
    const outer = ctx.createRadialGradient(0, 0, 1, 0, -12, 20);
    outer.addColorStop(0, "rgba(255, 248, 200, 0.95)");
    outer.addColorStop(0.28, "rgba(255, 170, 50, 0.85)");
    outer.addColorStop(0.7, "rgba(255, 80, 10, 0.35)");
    outer.addColorStop(1, "rgba(255, 30, 0, 0)");
    ctx.fillStyle = outer;
    ctx.beginPath();
    ctx.moveTo(-6, 5);
    ctx.quadraticCurveTo(-9 + wobble, -7, 0, -20 - Math.abs(wobble));
    ctx.quadraticCurveTo(9 - wobble, -7, 6, 5);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = "rgba(255, 252, 230, 0.95)";
    ctx.beginPath();
    ctx.ellipse(0, -2, 2.1, 6.2, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  function drawMatchStick(life) {
    const wood = ctx.createLinearGradient(-3, 0, 3, 0);
    wood.addColorStop(0, "#7a5428");
    wood.addColorStop(0.45, "#e2c088");
    wood.addColorStop(1, "#5a3a16");
    ctx.fillStyle = wood;
    ctx.fillRect(-2.4, -10, 4.8, 24);
    const head = ctx.createRadialGradient(-0.6, -13, 0.4, 0, -12, 4);
    head.addColorStop(0, life > 0.08 ? "#ffd36a" : "#f2c2b0");
    head.addColorStop(0.45, "#d44828");
    head.addColorStop(1, "#6a1410");
    ctx.fillStyle = head;
    ctx.beginPath();
    ctx.ellipse(0, -12, 3.3, 3.7, 0, 0, Math.PI * 2);
    ctx.fill();
    if (life > 0.08) drawFlame(0, -16, 0.58);
  }

  function drawMatchBody(body) {
    ctx.save();
    ctx.translate(body.position.x, body.position.y);
    ctx.rotate(body.angle);
    drawMatchStick(body.plugin.life);
    ctx.restore();
  }

  function drawCursorMatch() {
    if (state.tool !== TOOL.MATCH || !state.started) return;
    ctx.save();
    ctx.translate(state.pointer.x + 10, state.pointer.y - 8);
    ctx.rotate(-0.5);
    drawMatchStick(1);
    ctx.restore();
  }

  function drawGhost() {
    if (!state.started) return;
    let w = 0;
    let h = 0;
    let color = "#d96a4a";
    if (state.tool === TOOL.STOVE) {
      const preset = currentStove();
      const origin = stoveOriginAt(state.pointer.x, state.pointer.y);
      const ok = stoveFits(origin, preset);
      ctx.save();
      ctx.globalAlpha = 0.38;
      ctx.fillStyle = ok ? "#d96a4a" : "#5a2a24";
      ctx.strokeStyle = ok ? "#f0c08a" : "#a06060";
      ctx.setLineDash([4, 4]);
      preset.bricks.forEach(([col, row]) => {
        const pos = stoveBrickPos(origin, preset, col, row);
        roundRect(ctx, pos.x - BRICK_W / 2, pos.y - BRICK_H / 2, BRICK_W, BRICK_H, 2);
        ctx.fill();
        ctx.stroke();
      });
      const pipe = stovePipePos(origin, preset);
      ctx.fillStyle = ok ? "#9aa3aa" : "#5a2a24";
      roundRect(ctx, pipe.x - PIPE_W / 2, pipe.y - PIPE_H / 2, PIPE_W, PIPE_H, 2);
      ctx.fill();
      ctx.stroke();
      ctx.restore();
      return;
    }
    if (state.tool === TOOL.BRICK) {
      ({ w, h } = brickSize());
    } else if (state.tool === TOOL.SAWDUST) {
      ctx.save();
      ctx.globalAlpha = 0.45;
      for (let i = 0; i < 10; i += 1) {
        const ox = (i % 5 - 2) * 5;
        const oy = ((i / 5) | 0) * 4 - 6;
        ctx.fillStyle = "#c4a06a";
        ctx.fillRect(state.pointer.x + ox - 3, state.pointer.y + oy - 1, 6, 2.2);
      }
      ctx.restore();
      return;
    } else if (state.tool === TOOL.PIPE) {
      w = PIPE_W;
      h = PIPE_H;
      color = "#9aa3aa";
    } else if (state.tool === TOOL.PROP) {
      ({ w, h } = propSize());
      color = "#c49a5a";
    } else {
      return;
    }
    const at = placePoint(state.pointer.x, state.pointer.y, w, h);
    const ok = canPlace(at.x, at.y, w, h);
    ctx.save();
    ctx.globalAlpha = 0.4;
    ctx.fillStyle = ok ? color : "#5a2a24";
    ctx.strokeStyle = ok ? "#f0c08a" : "#a06060";
    ctx.setLineDash([4, 4]);
    roundRect(ctx, at.x - w / 2, at.y - h / 2, w, h, 2);
    ctx.fill();
    ctx.stroke();
    ctx.restore();
  }

  function drawSmoke() {
    state.smoke.forEach((p) => {
      const alpha = 0.26 + p.dark * 0.12;
      const grd = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.size * 1.15);
      const c = Math.floor(36 + (1 - p.dark) * 100);
      grd.addColorStop(0, `rgba(${c + 28}, ${c + 24}, ${c + 20}, ${alpha})`);
      grd.addColorStop(0.45, `rgba(${c + 8}, ${c + 8}, ${c + 10}, ${alpha * 0.62})`);
      grd.addColorStop(1, `rgba(${c}, ${c}, ${c}, 0)`);
      ctx.fillStyle = grd;
      ctx.beginPath();
      ctx.ellipse(p.x, p.y, p.size * 1.05, p.size * 0.82, p.x * 0.01, 0, Math.PI * 2);
      ctx.fill();
    });
  }

  function drawParticles() {
    state.particles = state.particles.filter((p) => p.life > 0);
    state.particles.forEach((p) => {
      p.x += p.vx;
      p.y += p.vy;
      p.vy += 0.05;
      p.life -= 0.02;
      ctx.globalAlpha = Math.max(0, p.life);
      ctx.fillStyle = p.color;
      ctx.fillRect(p.x, p.y, p.size, p.size);
      ctx.globalAlpha = 1;
    });
  }

  function drawFires() {
    const burning = fires();
    burning.forEach((fuel, index) => {
      if (fuel.label === "prop") {
        const w = fuel.plugin.w;
        const h = fuel.plugin.h;
        const along = Math.max(w, h);
        const count = Math.max(4, Math.floor(along / 55));
        const c = Math.cos(fuel.angle);
        const s = Math.sin(fuel.angle);
        for (let i = 0; i < count; i += 1) {
          const t = (i + 0.5) / count - 0.5;
          const lx = w >= h ? t * w : 0;
          const ly = h > w ? t * h : 0;
          const x = fuel.position.x + lx * c - ly * s;
          const y = fuel.position.y + lx * s + ly * c;
          const flicker = 0.42 + Math.sin(state.time * 0.28 + fuel.id + i) * 0.1;
          drawFlame(x, y - 10, flicker);
        }
        return;
      }
      if (index % 2 !== state.time % 2 && burning.length > 14) return;
      const flicker = 0.42 + Math.sin(state.time * 0.3 + fuel.id) * 0.1;
      drawFlame(fuel.position.x, fuel.position.y - 7, flicker);
    });
  }

  function roundRect(context, x, y, w, h, r) {
    context.beginPath();
    context.moveTo(x + r, y);
    context.arcTo(x + w, y, x + w, y + h, r);
    context.arcTo(x + w, y + h, x, y + h, r);
    context.arcTo(x, y + h, x, y, r);
    context.arcTo(x, y, x + w, y, r);
    context.closePath();
  }

  function withCamera(fn) {
    ctx.save();
    ctx.translate(width / 2, height / 2);
    ctx.scale(state.camera.zoom, state.camera.zoom);
    ctx.translate(-width / 2 - state.camera.x, -height / 2 - state.camera.y);
    fn();
    ctx.restore();
  }

  function settleBodies() {
    [state.bricksList, state.props, state.pipeList, state.fuels, state.ashes].forEach((list) => {
      list.forEach((body) => {
        if (body.isStatic || body.isSleeping) return;
        const speed = Math.hypot(body.velocity.x, body.velocity.y);
        if (speed < 0.07 && Math.abs(body.angularVelocity) < 0.018) {
          Body.setVelocity(body, { x: 0, y: 0 });
          Body.setAngularVelocity(body, 0);
        }
      });
    });
  }

  function updateCamera() {
    const speed = 7 / state.camera.zoom;
    if (keys.has("KeyA") || keys.has("ArrowLeft")) state.camera.x -= speed;
    if (keys.has("KeyD") || keys.has("ArrowRight")) state.camera.x += speed;
    if (keys.has("KeyW") || keys.has("ArrowUp")) state.camera.y -= speed;
    if (keys.has("KeyS") || keys.has("ArrowDown")) state.camera.y += speed;
    syncMouse();
  }

  function tick() {
    state.time += 1;
    if (state.started && state.pointer.down && state.tool === TOOL.SAWDUST && state.time - state.lastPour > 9) {
      spawnSawdust(state.pointer.x, state.pointer.y);
    }
    updateCamera();
    const step = 1000 / 60 / PHYS_SUBSTEPS;
    for (let i = 0; i < PHYS_SUBSTEPS; i += 1) Engine.update(engine, step);
    if (state.time % 3 === 0) settleBodies();
    updateFire();
    updateMatches();
    updateSmoke();
    if (state.time % 8 === 0) {
      refreshJoints();
      reclaimFallen();
    }

    drawBackground();
    withCamera(() => {
      drawFoundation();
      drawShadows();
      drawJoints();
      state.bricksList.forEach(drawBrickBody);
      state.pipeList.forEach(drawPipe);
      state.props.forEach(drawProp);
      state.fuels.forEach(drawSawdust);
      drawAshes();
      state.matches.forEach(drawMatchBody);
      drawFires();
      drawSmoke();
      drawGhost();
      drawCursorMatch();
      drawParticles();
    });
    drawColorGrade();

    requestAnimationFrame(tick);
  }

  function toggleBond() {
    state.runningBond = !state.runningBond;
    bondLabel.textContent = state.runningBond ? "Перевязка" : "Столбик";
    hintEl.textContent = state.runningBond
      ? "Перевязка: каждый ряд со сдвигом."
      : "Столбик: швы друг над другом.";
  }

  function toggleSnap() {
    state.snap = !state.snap;
    snapLabel.textContent = state.snap ? "Сетка" : "Свободно";
    document.getElementById("btn-snap").classList.toggle("active", state.snap);
    hintEl.textContent = state.snap
      ? "Автовыравнивание включено: кирпич садится на сетку."
      : "Сетка выключена: клади туда, куда кликнул. Кирпич всё равно физический.";
  }

  document.getElementById("tool-hand").addEventListener("click", () => setTool(TOOL.HAND));
  document.getElementById("tool-brick").addEventListener("click", () => setTool(TOOL.BRICK));
  document.getElementById("tool-cement").addEventListener("click", () => setTool(TOOL.CEMENT));
  document.getElementById("tool-sawdust").addEventListener("click", () => setTool(TOOL.SAWDUST));
  document.getElementById("tool-match").addEventListener("click", () => setTool(TOOL.MATCH));
  document.getElementById("tool-pipe").addEventListener("click", () => setTool(TOOL.PIPE));
  document.getElementById("tool-prop").addEventListener("click", () => setTool(TOOL.PROP));
  document.querySelectorAll(".catalog button").forEach((btn) => {
    btn.addEventListener("click", () => selectStove(btn.dataset.stove));
  });
  document.getElementById("btn-rotate").addEventListener("click", () => {
    state.rotated = !state.rotated;
  });
  document.getElementById("btn-bond").addEventListener("click", toggleBond);
  document.getElementById("btn-snap").addEventListener("click", toggleSnap);
  document.getElementById("btn-clean").addEventListener("click", cleanStove);
  document.getElementById("btn-delete").addEventListener("click", deleteStove);
  document.getElementById("btn-start").addEventListener("click", () => {
    state.started = true;
    intro.classList.add("hidden");
    setTool(TOOL.BRICK);
  });

  window.addEventListener("resize", resize);
  window.addEventListener("pointermove", onPointerMove);
  window.addEventListener("pointerdown", onPointerDown);
  window.addEventListener("pointerup", onPointerUp);
  window.addEventListener("contextmenu", (e) => {
    if (e.target === canvas) {
      e.preventDefault();
      state.rotated = !state.rotated;
    }
  });
  window.addEventListener("keydown", (e) => {
    keys.add(e.code);
    if (e.code === "Digit1") setTool(TOOL.BRICK);
    if (e.code === "Digit2") setTool(TOOL.CEMENT);
    if (e.code === "Digit3") setTool(TOOL.SAWDUST);
    if (e.code === "Digit4") setTool(TOOL.MATCH);
    if (e.code === "Digit5") setTool(TOOL.PIPE);
    if (e.code === "Digit6") setTool(TOOL.PROP);
    if (e.code === "Digit7") selectStove(state.stoveId);
    if (e.code === "KeyQ") setTool(TOOL.HAND);
    if (e.code === "KeyR") state.rotated = !state.rotated;
    if (e.code === "KeyT") toggleBond();
    if (e.code === "KeyG") toggleSnap();
    if (e.code === "Escape") setTool(TOOL.HAND);
  });
  window.addEventListener("keyup", (e) => keys.delete(e.code));
  canvas.addEventListener(
    "wheel",
    (e) => {
      e.preventDefault();
      state.camera.zoom = Math.min(1.8, Math.max(0.55, state.camera.zoom * (e.deltaY > 0 ? 0.92 : 1.08)));
      syncMouse();
    },
    { passive: false }
  );

  Events.on(engine, "collisionStart", (event) => {
    event.pairs.forEach((pair) => {
      const labels = [pair.bodyA.label, pair.bodyB.label];
      if (labels.includes("match") && (labels.includes("sawdust") || labels.includes("prop"))) {
        const fuel = pair.bodyA.label === "match" ? pair.bodyB : pair.bodyA;
        igniteFuel(fuel);
      }
      if (pair.collision.depth > 1.4 && labels.includes("brick")) {
        burst((pair.bodyA.position.x + pair.bodyB.position.x) / 2, (pair.bodyA.position.y + pair.bodyB.position.y) / 2, "#8a5a48", 3);
      }
    });
  });

  function buildDemo() {
    state.started = true;
    intro.classList.add("hidden");
    setTool(TOOL.BRICK);
    state.runningBond = false;
    [
      [0, 0],
      [1, 0],
      [2, 0],
      [3, 0],
      [4, 0],
      [0, 1],
      [4, 1],
      [0, 2],
      [4, 2],
      [0, 3],
      [1, 3],
      [2, 3],
      [3, 3],
      [4, 3],
    ].forEach(([col, row]) => {
      const pos = cellPos(col, row, false);
      spawnBrick(pos.x, pos.y);
      applyCementNear(state.bricksList[state.bricksList.length - 1], true);
    });
    const fuelY = groundY - 20 - BRICK_H - 14;
    const grains = spawnSawdust(originX, fuelY);
    grains.slice(0, 10).forEach((grain) => igniteFuel(grain));
    const roof = cellPos(4, 3, false);
    spawnPipe(roof.x, roof.y - BRICK_H / 2 - PIPE_H / 2 - 1);
    hintEl.textContent = "Демо: топка горит, дым ищет трубу.";
  }

  resize();
  updateTempUi();
  const params = new URLSearchParams(window.location.search);
  if (params.has("demo")) buildDemo();
  else setTool(TOOL.BRICK);
  requestAnimationFrame(tick);
})();
