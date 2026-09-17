#include "raylib.h"
#include "raymath.h"
#include "lighting.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_BODIES 720
#define MAX_WELDS 900
#define MAX_PART 900
#define BRICK_X 0.25f
#define BRICK_Y 0.12f
#define BRICK_Z 0.12f
#define PIPE_X 0.10f
#define PIPE_Y 0.42f
#define PIPE_Z 0.10f
#define PROP_X 0.07f
#define PROP_Y 0.60f
#define PROP_Z 0.07f
#define GROUND_Y 0.0f

typedef enum {
    KIND_BRICK = 0,
    KIND_PIPE,
    KIND_PROP,
    KIND_DUST,
    KIND_ASH
} Kind;

typedef enum {
    TOOL_HAND = 0,
    TOOL_BRICK,
    TOOL_CEMENT,
    TOOL_SAWDUST,
    TOOL_MATCH,
    TOOL_PIPE,
    TOOL_PROP,
    TOOL_COUNT
} Tool;

typedef struct {
    int alive;
    Kind kind;
    Vector3 pos;
    Vector3 vel;
    Vector3 size;
    float yaw;
    int burning;
    float fuel;
    float heat;
    unsigned seed;
} Body;

typedef struct {
    int a, b;
    Vector3 offset;
    int used;
} Weld;

typedef struct {
    Vector3 pos;
    Vector3 vel;
    float life;
    float size;
    Color color;
    int smoke;
} Part;

static Body bodies[MAX_BODIES];
static Weld welds[MAX_WELDS];
static Part parts[MAX_PART];
static int bodyCount = 0;
static int weldCount = 0;
static int partCount = 0;
static Tool tool = TOOL_BRICK;
static int runningBond = 1;
static float camYaw = 0.65f;
static float camPitch = 0.42f;
static float camDist = 6.2f;
static Vector3 camTarget = { 0, 0.4f, 0 };
static float stoveTemp = 20.0f;
static Texture2D texBrick, texWood, texMetal, texGround, texWall, texGrass, texWhite;
static Mesh meshBox, meshFloor, meshGrass;
static Material matLit;
static Shader shader;
static Font font;

static unsigned hashu(unsigned n) {
    n = (n ^ 61u) ^ (n >> 16);
    n *= 9u;
    n = n ^ (n >> 4);
    n *= 0x27d4eb2du;
    n = n ^ (n >> 15);
    return n;
}

static float frand(unsigned *s) {
    *s = hashu(*s + 1);
    return (*s & 0xffff) / 65535.0f;
}

static const char *toolName(Tool t) {
    switch (t) {
        case TOOL_HAND: return "Рука";
        case TOOL_BRICK: return "Кирпич";
        case TOOL_CEMENT: return "Цемент";
        case TOOL_SAWDUST: return "Опилки";
        case TOOL_MATCH: return "Спичка";
        case TOOL_PIPE: return "Труба";
        case TOOL_PROP: return "Подпорка";
        default: return "";
    }
}

static Vector3 kindSize(Kind k) {
    switch (k) {
        case KIND_PIPE: return (Vector3){ PIPE_X, PIPE_Y, PIPE_Z };
        case KIND_PROP: return (Vector3){ PROP_X, PROP_Y, PROP_Z };
        case KIND_DUST: return (Vector3){ 0.018f, 0.010f, 0.014f };
        case KIND_ASH: return (Vector3){ 0.016f, 0.008f, 0.014f };
        default: return (Vector3){ BRICK_X, BRICK_Y, BRICK_Z };
    }
}

static int spawnBody(Kind k, Vector3 p, Vector3 vel) {
    if (bodyCount >= MAX_BODIES) return -1;
    int id = bodyCount++;
    bodies[id] = (Body){ 0 };
    bodies[id].alive = 1;
    bodies[id].kind = k;
    bodies[id].pos = p;
    bodies[id].vel = vel;
    bodies[id].size = kindSize(k);
    bodies[id].seed = (unsigned)(id * 7919 + GetRandomValue(1, 9999));
    if (k == KIND_PROP) bodies[id].fuel = 2.4f;
    if (k == KIND_DUST) bodies[id].fuel = 0.7f + (GetRandomValue(0, 30) / 100.0f);
    return id;
}

static void burst(Vector3 p, Color c, int n, int smoke) {
    for (int i = 0; i < n && partCount < MAX_PART; i++) {
        Part *q = &parts[partCount++];
        q->pos = p;
        q->vel = (Vector3){
            (GetRandomValue(-100, 100) / 80.0f),
            0.6f + GetRandomValue(0, 80) / 80.0f,
            (GetRandomValue(-100, 100) / 80.0f)
        };
        q->life = smoke ? 2.8f : 0.7f;
        q->size = smoke ? 0.10f + GetRandomValue(0, 20) / 120.0f : 0.03f;
        q->color = c;
        q->smoke = smoke;
    }
}

static int aabbOverlap(const Body *a, const Body *b, Vector3 *pen) {
    float dx = fabsf(a->pos.x - b->pos.x) - (a->size.x + b->size.x) * 0.5f;
    float dy = fabsf(a->pos.y - b->pos.y) - (a->size.y + b->size.y) * 0.5f;
    float dz = fabsf(a->pos.z - b->pos.z) - (a->size.z + b->size.z) * 0.5f;
    if (dx >= 0 || dy >= 0 || dz >= 0) return 0;
    if (-dx <= -dy && -dx <= -dz) {
        *pen = (Vector3){ (a->pos.x < b->pos.x ? dx : -dx), 0, 0 };
    } else if (-dy <= -dz) {
        *pen = (Vector3){ 0, (a->pos.y < b->pos.y ? dy : -dy), 0 };
    } else {
        *pen = (Vector3){ 0, 0, (a->pos.z < b->pos.z ? dz : -dz) };
    }
    return 1;
}

static int nearBodies(int i, int j, float pad) {
    Body *a = &bodies[i], *b = &bodies[j];
    float dx = fabsf(a->pos.x - b->pos.x) - (a->size.x + b->size.x) * 0.5f;
    float dy = fabsf(a->pos.y - b->pos.y) - (a->size.y + b->size.y) * 0.5f;
    float dz = fabsf(a->pos.z - b->pos.z) - (a->size.z + b->size.z) * 0.5f;
    return dx < pad && dy < pad && dz < pad;
}

static void addWeld(int a, int b) {
    if (a == b || a < 0 || b < 0) return;
    for (int i = 0; i < weldCount; i++) {
        if (welds[i].used && ((welds[i].a == a && welds[i].b == b) || (welds[i].a == b && welds[i].b == a)))
            return;
    }
    if (weldCount >= MAX_WELDS) return;
    welds[weldCount++] = (Weld){
        a, b,
        Vector3Subtract(bodies[b].pos, bodies[a].pos),
        1
    };
    burst(Vector3Lerp(bodies[a].pos, bodies[b].pos, 0.5f), (Color){ 230, 214, 180, 255 }, 8, 0);
}

static void cementAt(Vector3 p) {
    int bestA = -1, bestB = -1;
    float best = 0.28f;
    for (int i = 0; i < bodyCount; i++) if (bodies[i].alive && (bodies[i].kind == KIND_BRICK || bodies[i].kind == KIND_PIPE)) {
        for (int j = i + 1; j < bodyCount; j++) if (bodies[j].alive && (bodies[j].kind == KIND_BRICK || bodies[j].kind == KIND_PIPE)) {
            if (!nearBodies(i, j, 0.06f)) continue;
            Vector3 mid = Vector3Lerp(bodies[i].pos, bodies[j].pos, 0.5f);
            float d = Vector3Distance(mid, p);
            if (d < best) { best = d; bestA = i; bestB = j; }
        }
    }
    if (bestA >= 0) addWeld(bestA, bestB);
}

static void igniteNear(Vector3 p, float r) {
    for (int i = 0; i < bodyCount; i++) {
        Body *b = &bodies[i];
        if (!b->alive || b->burning) continue;
        if (b->kind != KIND_DUST && b->kind != KIND_PROP) continue;
        if (Vector3Distance(b->pos, p) < r) {
            b->burning = 1;
            burst(b->pos, (Color){ 255, 160, 40, 255 }, 10, 0);
        }
    }
}

static Color mixc(Color a, Color b, float t) {
    return (Color){
        (unsigned char)(a.r + (b.r - a.r) * t),
        (unsigned char)(a.g + (b.g - a.g) * t),
        (unsigned char)(a.b + (b.b - a.b) * t),
        255
    };
}

static void speckleRect(Image *img, unsigned *s, int x, int y, int w, int h, int n, Color a, Color b) {
    for (int i = 0; i < n; i++) {
        int px = x + (int)(frand(s) * (w <= 1 ? 1 : w));
        int py = y + (int)(frand(s) * (h <= 1 ? 1 : h));
        ImageDrawPixel(img, px, py, mixc(a, b, frand(s)));
    }
}

static void speckle(Image *img, unsigned *s, int n, Color a, Color b) {
    speckleRect(img, s, 0, 0, img->width, img->height, n, a, b);
}

static Texture2D imageToTex(Image img, int repeat) {
    Texture2D tex = LoadTextureFromImage(img);
    UnloadImage(img);
    SetTextureFilter(tex, TEXTURE_FILTER_BILINEAR);
    if (repeat) SetTextureWrap(tex, TEXTURE_WRAP_REPEAT);
    return tex;
}

static void paintBrick(Image *img, int x, int y, int bw, int bh, unsigned *s) {
    Color clay[] = {
        { 168, 68, 44, 255 }, { 186, 82, 52, 255 }, { 142, 56, 38, 255 },
        { 198, 96, 58, 255 }, { 154, 60, 40, 255 }, { 176, 74, 48, 255 }
    };
    Color base = clay[(int)(frand(s) * 6) % 6];
    ImageDrawRectangle(img, x, y, bw, bh, base);
    speckleRect(img, s, x, y, bw, bh, 50, (Color){ 90, 30, 18, 255 }, (Color){ 230, 150, 100, 255 });
    ImageDrawRectangle(img, x, y, bw, 3, mixc(base, WHITE, 0.22f));
    ImageDrawRectangle(img, x, y + bh - 3, bw, 3, mixc(base, BLACK, 0.28f));
    ImageDrawRectangle(img, x, y, 3, bh, mixc(base, BLACK, 0.18f));
    ImageDrawRectangle(img, x + bw - 3, y, 3, bh, mixc(base, WHITE, 0.12f));
}

static Texture2D makeBrickTex(void) {
    Image img = GenImageColor(256, 128, (Color){ 186, 168, 140, 255 });
    unsigned s = 1103;
    paintBrick(&img, 6, 6, 244, 116, &s);
    return imageToTex(img, 0);
}

static Texture2D makeWallTex(void) {
    const int w = 512, h = 512;
    Image img = GenImageColor(w, h, (Color){ 188, 172, 148, 255 });
    unsigned s = 2201;
    const int bh = 36, bw = 78, gap = 5;
    for (int row = 0, y = 0; y < h; row++, y += bh + gap) {
        int ox = (row & 1) ? -(bw / 2) : 0;
        for (int x = ox; x < w; x += bw + gap) {
            int px = x < 0 ? 0 : x;
            int pw = (x < 0) ? bw + x : ((x + bw > w) ? w - x : bw);
            if (pw > 8) paintBrick(&img, px, y, pw, bh, &s);
        }
    }
    return imageToTex(img, 1);
}

static Texture2D makeWoodTex(void) {
    const int w = 256, h = 256;
    Image img = GenImageColor(w, h, (Color){ 128, 82, 42, 255 });
    unsigned s = 4401;
    int plank = 42;
    for (int x = 0; x < w; x += plank) {
        Color a = mixc((Color){ 96, 58, 28, 255 }, (Color){ 168, 112, 58, 255 }, frand(&s));
        ImageDrawRectangle(&img, x, 0, plank - 3, h, a);
        ImageDrawRectangle(&img, x + plank - 3, 0, 3, h, (Color){ 52, 30, 14, 255 });
        for (int y = 0; y < h; y++) {
            float wave = sinf(y * 0.11f + x * 0.03f) * 0.15f + 0.5f;
            ImageDrawPixel(&img, x + 6 + (int)(wave * (plank - 16)), y, mixc(a, (Color){ 70, 40, 18, 255 }, 0.35f));
        }
    }
    speckle(&img, &s, 2000, (Color){ 60, 32, 14, 255 }, (Color){ 210, 170, 100, 255 });
    return imageToTex(img, 1);
}

static Texture2D makeMetalTex(void) {
    const int w = 128, h = 256;
    Image img = GenImageColor(w, h, (Color){ 120, 126, 132, 255 });
    unsigned s = 77;
    for (int x = 0; x < w; x++) {
        float t = 1.0f - fabsf((x / (float)w) - 0.38f) * 1.8f;
        if (t < 0) t = 0;
        Color c = mixc((Color){ 64, 68, 72, 255 }, (Color){ 236, 240, 244, 255 }, t);
        for (int y = 0; y < h; y++) ImageDrawPixel(&img, x, y, c);
    }
    ImageDrawRectangle(&img, 0, 40, w, 6, (Color){ 40, 42, 44, 255 });
    ImageDrawRectangle(&img, 0, h - 48, w, 6, (Color){ 40, 42, 44, 255 });
    speckle(&img, &s, 600, (Color){ 90, 50, 20, 255 }, (Color){ 200, 200, 200, 255 });
    return imageToTex(img, 0);
}

static Texture2D makeGroundTex(void) {
    const int w = 512, h = 512;
    Image img = GenImageColor(w, h, (Color){ 150, 144, 132, 255 });
    unsigned s = 909;
    const int tile = 64;
    for (int y = 0; y < h; y += tile) {
        for (int x = 0; x < w; x += tile) {
            Color c = mixc((Color){ 138, 132, 120, 255 }, (Color){ 172, 166, 150, 255 }, frand(&s));
            ImageDrawRectangle(&img, x + 2, y + 2, tile - 4, tile - 4, c);
            ImageDrawRectangle(&img, x, y, tile, 2, (Color){ 110, 104, 94, 255 });
            ImageDrawRectangle(&img, x, y, 2, tile, (Color){ 110, 104, 94, 255 });
        }
    }
    speckle(&img, &s, 8000, (Color){ 90, 86, 78, 255 }, (Color){ 200, 194, 176, 255 });
    return imageToTex(img, 1);
}

static Texture2D makeGrassTex(void) {
    const int w = 512, h = 512;
    Image img = GenImageColor(w, h, (Color){ 78, 118, 48, 255 });
    unsigned s = 515;
    speckle(&img, &s, 22000, (Color){ 48, 86, 28, 255 }, (Color){ 130, 168, 70, 255 });
    for (int i = 0; i < 400; i++) {
        int x = (int)(frand(&s) * w);
        int y = (int)(frand(&s) * h);
        ImageDrawLine(&img, x, y, x, y - 4 - (int)(frand(&s) * 5), (Color){ 60, 140, 40, 255 });
    }
    return imageToTex(img, 1);
}

static Mesh makeTiledPlane(float w, float d, float tilesU, float tilesV) {
    Mesh m = GenMeshPlane(w, d, 1, 1);
    if (m.texcoords) {
        for (int i = 0; i < m.vertexCount; i++) {
            m.texcoords[i * 2 + 0] *= tilesU;
            m.texcoords[i * 2 + 1] *= tilesV;
        }
        UpdateMeshBuffer(m, 1, m.texcoords, (int)(m.vertexCount * 2 * sizeof(float)), 0);
    }
    return m;
}

static Font loadRuFont(int size) {
    const char *paths[] = {
        "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/tahoma.ttf",
        "C:/Windows/Fonts/calibri.ttf",
        NULL
    };
    int cps[900];
    int n = 0;
    for (int i = 32; i < 127; i++) cps[n++] = i;
    for (int i = 0x400; i <= 0x45F; i++) cps[n++] = i;
    cps[n++] = 0x401;
    cps[n++] = 0x451;
    cps[n++] = 0x2014;
    cps[n++] = 0x2116;
    cps[n++] = 0x00B0;
    for (int i = 0; paths[i]; i++) {
        if (!FileExists(paths[i])) continue;
        Font f = LoadFontEx(paths[i], size, cps, n);
        if (f.texture.id != 0) {
            SetTextureFilter(f.texture, TEXTURE_FILTER_BILINEAR);
            return f;
        }
    }
    return GetFontDefault();
}

static Texture2D loadPhoto(const char *file, Texture2D (*fallback)(void)) {
    char path[1024];
    snprintf(path, sizeof path, "%sassets/%s", GetApplicationDirectory(), file);
    if (!FileExists(path)) snprintf(path, sizeof path, "assets/%s", file);
    if (!FileExists(path)) snprintf(path, sizeof path, "../assets/%s", file);
    if (FileExists(path)) {
        Texture2D t = LoadTexture(path);
        if (t.id != 0) {
            GenTextureMipmaps(&t);
            SetTextureFilter(t, TEXTURE_FILTER_TRILINEAR);
            SetTextureWrap(t, TEXTURE_WRAP_REPEAT);
            return t;
        }
    }
    return fallback();
}

static void setupGfx(void) {
    texBrick = loadPhoto("clay.jpg", makeBrickTex);
    texWood = loadPhoto("wood.jpg", makeWoodTex);
    texMetal = loadPhoto("metal.jpg", makeMetalTex);
    texGround = loadPhoto("concrete.jpg", makeGroundTex);
    texWall = loadPhoto("brick_wall.jpg", makeWallTex);
    texGrass = loadPhoto("grass.jpg", makeGrassTex);
    Image white = GenImageColor(4, 4, WHITE);
    texWhite = LoadTextureFromImage(white);
    UnloadImage(white);

    meshBox = GenMeshCube(1, 1, 1);
    meshFloor = makeTiledPlane(18.0f, 14.0f, 12.0f, 9.0f);
    meshGrass = makeTiledPlane(80.0f, 80.0f, 40.0f, 40.0f);
    shader = LoadShaderFromMemory(LIGHT_VS, LIGHT_FS);
    shader.locs[SHADER_LOC_MATRIX_MVP] = GetShaderLocation(shader, "mvp");
    shader.locs[SHADER_LOC_MATRIX_MODEL] = GetShaderLocation(shader, "matModel");
    shader.locs[SHADER_LOC_MATRIX_NORMAL] = GetShaderLocation(shader, "matNormal");
    shader.locs[SHADER_LOC_VECTOR_VIEW] = GetShaderLocation(shader, "viewPos");
    shader.locs[SHADER_LOC_MAP_DIFFUSE] = GetShaderLocation(shader, "texture0");
    shader.locs[SHADER_LOC_COLOR_DIFFUSE] = GetShaderLocation(shader, "colDiffuse");
    matLit = LoadMaterialDefault();
    matLit.shader = shader;
    SetMaterialTexture(&matLit, MATERIAL_MAP_DIFFUSE, texBrick);
    font = loadRuFont(36);
}

static void drawBox(Vector3 p, Vector3 s, Texture2D tex, Color tint) {
    SetMaterialTexture(&matLit, MATERIAL_MAP_DIFFUSE, tex);
    matLit.maps[MATERIAL_MAP_DIFFUSE].color = tint;
    Matrix m = MatrixMultiply(MatrixScale(s.x, s.y, s.z), MatrixTranslate(p.x, p.y, p.z));
    DrawMesh(meshBox, matLit, m);
}

static void drawWorkshop(void) {
    SetMaterialTexture(&matLit, MATERIAL_MAP_DIFFUSE, texGrass);
    matLit.maps[MATERIAL_MAP_DIFFUSE].color = WHITE;
    DrawMesh(meshGrass, matLit, MatrixTranslate(0, -0.04f, 0));

    DrawSphere((Vector3){ 18, 16, 22 }, 2.4f, (Color){ 255, 236, 170, 255 });

    SetMaterialTexture(&matLit, MATERIAL_MAP_DIFFUSE, texGround);
    DrawMesh(meshFloor, matLit, MatrixTranslate(0, 0.001f, 0));

    SetMaterialTexture(&matLit, MATERIAL_MAP_DIFFUSE, texWall);
    DrawMesh(meshBox, matLit, MatrixMultiply(MatrixScale(18.2f, 5.2f, 0.28f), MatrixTranslate(0, 2.6f, -7.0f)));
    DrawMesh(meshBox, matLit, MatrixMultiply(MatrixScale(0.28f, 5.2f, 14.2f), MatrixTranslate(-9.0f, 2.6f, 0)));
    DrawMesh(meshBox, matLit, MatrixMultiply(MatrixScale(0.28f, 5.2f, 14.2f), MatrixTranslate(9.0f, 2.6f, 0)));
    DrawMesh(meshBox, matLit, MatrixMultiply(MatrixScale(4.4f, 5.2f, 0.28f), MatrixTranslate(-6.8f, 2.6f, 7.0f)));
    DrawMesh(meshBox, matLit, MatrixMultiply(MatrixScale(4.4f, 5.2f, 0.28f), MatrixTranslate(6.8f, 2.6f, 7.0f)));
    DrawMesh(meshBox, matLit, MatrixMultiply(MatrixScale(5.0f, 1.4f, 0.28f), MatrixTranslate(0, 4.5f, 7.0f)));

    SetMaterialTexture(&matLit, MATERIAL_MAP_DIFFUSE, texWood);
    DrawMesh(meshBox, matLit, MatrixMultiply(MatrixScale(0.28f, 5.2f, 0.28f), MatrixTranslate(-4.2f, 2.6f, -6.78f)));
    DrawMesh(meshBox, matLit, MatrixMultiply(MatrixScale(0.28f, 5.2f, 0.28f), MatrixTranslate(4.2f, 2.6f, -6.78f)));
    DrawMesh(meshBox, matLit, MatrixMultiply(MatrixScale(0.32f, 5.2f, 0.32f), MatrixTranslate(-2.4f, 2.6f, 6.86f)));
    DrawMesh(meshBox, matLit, MatrixMultiply(MatrixScale(0.32f, 5.2f, 0.32f), MatrixTranslate(2.4f, 2.6f, 6.86f)));
    {
        Matrix left = MatrixMultiply(MatrixScale(10.4f, 0.18f, 15.2f), MatrixMultiply(MatrixRotateZ(0.42f), MatrixTranslate(-3.6f, 6.15f, 0)));
        Matrix right = MatrixMultiply(MatrixScale(10.4f, 0.18f, 15.2f), MatrixMultiply(MatrixRotateZ(-0.42f), MatrixTranslate(3.6f, 6.15f, 0)));
        DrawMesh(meshBox, matLit, left);
        DrawMesh(meshBox, matLit, right);
    }

    SetMaterialTexture(&matLit, MATERIAL_MAP_DIFFUSE, texGround);
    matLit.maps[MATERIAL_MAP_DIFFUSE].color = (Color){ 210, 202, 184, 255 };
    DrawMesh(meshBox, matLit, MatrixMultiply(MatrixScale(3.1f, 0.14f, 2.2f), MatrixTranslate(0, 0.07f, 0)));
    matLit.maps[MATERIAL_MAP_DIFFUSE].color = WHITE;
}

static Vector3 snapPoint(Vector3 hit) {
    float cellX = BRICK_X + 0.008f;
    float cellZ = BRICK_Z + 0.008f;
    float cellY = BRICK_Y + 0.006f;
    int col = (int)floorf(hit.x / cellX + 0.5f);
    int row = (int)floorf(hit.z / cellZ + 0.5f);
    int layer = (int)floorf((hit.y - BRICK_Y * 0.5f) / cellY + 0.15f);
    if (layer < 0) layer = 0;
    float ox = (runningBond && (layer & 1)) ? cellX * 0.5f : 0;
    return (Vector3){ col * cellX + ox, 0.10f + BRICK_Y * 0.5f + layer * cellY, row * cellZ };
}

static RayCollision groundHit(Ray ray) {
    return GetRayCollisionBox(ray, (BoundingBox){ (Vector3){ -8, -0.2f, -6 }, (Vector3){ 8, 0.12f, 6 } });
}

static int pickBody(Ray ray) {
    int best = -1;
    float bestD = 40.0f;
    for (int i = 0; i < bodyCount; i++) if (bodies[i].alive) {
        Body *b = &bodies[i];
        BoundingBox box = {
            (Vector3){ b->pos.x - b->size.x * 0.5f, b->pos.y - b->size.y * 0.5f, b->pos.z - b->size.z * 0.5f },
            (Vector3){ b->pos.x + b->size.x * 0.5f, b->pos.y + b->size.y * 0.5f, b->pos.z + b->size.z * 0.5f }
        };
        RayCollision hit = GetRayCollisionBox(ray, box);
        if (hit.hit && hit.distance < bestD) { bestD = hit.distance; best = i; }
    }
    return best;
}

static void pourDust(Vector3 p) {
    for (int i = 0; i < 18; i++) {
        Vector3 q = {
            p.x + GetRandomValue(-20, 20) / 180.0f,
            p.y + 0.12f + GetRandomValue(0, 20) / 140.0f,
            p.z + GetRandomValue(-20, 20) / 180.0f
        };
        spawnBody(KIND_DUST, q, (Vector3){ GetRandomValue(-10, 10) / 80.0f, 0.1f, GetRandomValue(-10, 10) / 80.0f });
    }
}

static void updatePhysics(float dt) {
    const float g = 9.81f;
    for (int i = 0; i < bodyCount; i++) {
        Body *b = &bodies[i];
        if (!b->alive) continue;
        b->vel.y -= g * dt;
        b->vel = Vector3Scale(b->vel, 0.992f);
        b->pos = Vector3Add(b->pos, Vector3Scale(b->vel, dt));

        float floor = GROUND_Y + 0.10f + b->size.y * 0.5f;
        if (b->pos.y < floor) {
            b->pos.y = floor;
            if (b->vel.y < 0) b->vel.y = 0;
            b->vel.x *= 0.72f;
            b->vel.z *= 0.72f;
        }
    }

    for (int i = 0; i < bodyCount; i++) if (bodies[i].alive) {
        for (int j = i + 1; j < bodyCount; j++) if (bodies[j].alive) {
            Vector3 pen;
            if (!aabbOverlap(&bodies[i], &bodies[j], &pen)) continue;
            bodies[i].pos = Vector3Add(bodies[i].pos, Vector3Scale(pen, 0.5f));
            bodies[j].pos = Vector3Subtract(bodies[j].pos, Vector3Scale(pen, 0.5f));
            if (fabsf(pen.y) > fabsf(pen.x) && fabsf(pen.y) > fabsf(pen.z)) {
                if (pen.y < 0) bodies[i].vel.y = 0;
                else bodies[j].vel.y = 0;
            }
        }
    }

    for (int i = 0; i < weldCount; i++) if (welds[i].used) {
        Body *a = &bodies[welds[i].a];
        Body *b = &bodies[welds[i].b];
        if (!a->alive || !b->alive) { welds[i].used = 0; continue; }
        Vector3 want = Vector3Add(a->pos, welds[i].offset);
        Vector3 d = Vector3Subtract(want, b->pos);
        b->pos = Vector3Add(b->pos, Vector3Scale(d, 0.35f));
        a->pos = Vector3Subtract(a->pos, Vector3Scale(d, 0.35f));
        Vector3 avg = Vector3Scale(Vector3Add(a->vel, b->vel), 0.5f);
        a->vel = avg;
        b->vel = avg;
    }
}

static void updateFire(float dt) {
    int burning = 0;
    Vector3 fireP = { 0, 0.4f, 0 };
    for (int i = 0; i < bodyCount; i++) {
        Body *b = &bodies[i];
        if (!b->alive || !b->burning) continue;
        burning++;
        fireP = Vector3Add(fireP, b->pos);
        b->fuel -= dt * (b->kind == KIND_PROP ? 0.12f : 0.28f);
        if (GetRandomValue(0, 100) < 18) burst((Vector3){ b->pos.x, b->pos.y + 0.06f, b->pos.z }, (Color){ 70, 70, 70, 180 }, 1, 1);
        if (GetRandomValue(0, 100) < 8) {
            Vector3 ash = { b->pos.x, b->pos.y, b->pos.z };
            spawnBody(KIND_ASH, ash, (Vector3){ GetRandomValue(-8, 8) / 70.0f, 0.05f, GetRandomValue(-8, 8) / 70.0f });
        }
        for (int j = 0; j < bodyCount; j++) {
            Body *o = &bodies[j];
            if (!o->alive || o->burning) continue;
            if (o->kind != KIND_DUST && o->kind != KIND_PROP) continue;
            if (Vector3Distance(b->pos, o->pos) < 0.16f && GetRandomValue(0, 100) < 6) o->burning = 1;
        }
        if (b->fuel <= 0) {
            if (b->kind == KIND_PROP) {
                for (int k = 0; k < 16; k++) spawnBody(KIND_ASH, b->pos, (Vector3){ GetRandomValue(-12, 12) / 50.0f, 0.2f, GetRandomValue(-12, 12) / 50.0f });
            }
            b->alive = 0;
        }
    }
    if (burning) fireP = Vector3Scale(fireP, 1.0f / (float)burning);
    stoveTemp += burning * 18.0f * dt;
    stoveTemp -= (stoveTemp - 20.0f) * 0.08f * dt;
    if (stoveTemp < 20) stoveTemp = 20;
    if (stoveTemp > 860) stoveTemp = 860;

    float power = burning ? fminf(6.0f, burning * 0.12f) : 0.0f;
    SetShaderValue(shader, GetShaderLocation(shader, "firePos"), &fireP, SHADER_UNIFORM_VEC3);
    SetShaderValue(shader, GetShaderLocation(shader, "firePower"), &power, SHADER_UNIFORM_FLOAT);

    for (int i = 0; i < partCount; ) {
        Part *p = &parts[i];
        p->life -= dt;
        p->pos = Vector3Add(p->pos, Vector3Scale(p->vel, dt));
        if (p->smoke) {
            p->vel.y += 0.55f * dt;
            p->vel.x *= 0.99f;
            p->size += dt * 0.05f;
        } else {
            p->vel.y -= 9.0f * dt;
        }
        if (p->life <= 0) parts[i] = parts[--partCount];
        else i++;
    }
}

static void placeStove(Vector3 origin) {
    int cells[][2] = {
        {0,0},{1,0},{2,0},{3,0},{4,0},
        {0,1},{4,1},
        {0,2},{4,2},
        {0,3},{1,3},{2,3},{3,3},{4,3}
    };
    float cellX = BRICK_X + 0.008f;
    float cellY = BRICK_Y + 0.006f;
    for (int i = 0; i < 14; i++) {
        int col = cells[i][0] - 2;
        int layer = cells[i][1];
        Vector3 p = {
            origin.x + col * cellX,
            0.10f + BRICK_Y * 0.5f + layer * cellY,
            origin.z
        };
        spawnBody(KIND_BRICK, p, (Vector3){ 0, 0, 0 });
    }
    int start = bodyCount - 14;
    for (int i = start; i < bodyCount; i++) {
        for (int j = i + 1; j < bodyCount; j++) {
            if (nearBodies(i, j, 0.03f)) addWeld(i, j);
        }
    }
    spawnBody(KIND_PIPE, (Vector3){ origin.x + 2 * cellX, 0.10f + BRICK_Y * 0.5f + 4 * cellY + PIPE_Y * 0.5f, origin.z }, (Vector3){0,0,0});
    addWeld(bodyCount - 2, bodyCount - 1);
}

static void text(const char *s, float x, float y, float size, Color c) {
    DrawTextEx(font, s, (Vector2){ x, y }, size, 0.6f, c);
}

static void drawHud(int w, int h) {
    DrawRectangle(18, 16, 420, 92, (Color){ 12, 8, 6, 210 });
    DrawRectangle(18, 16, 6, 92, (Color){ 214, 140, 64, 255 });
    text("Печка", 36, 24, 30, (Color){ 250, 232, 200, 255 });
    char buf[160];
    snprintf(buf, sizeof buf, "Температура  %.0f град.", stoveTemp);
    text(buf, 36, 62, 22, (Color){ 236, 180, 96, 255 });

    DrawRectangle(18, h - 86, 640, 70, (Color){ 12, 8, 6, 210 });
    snprintf(buf, sizeof buf, "Сейчас: %s", toolName(tool));
    text(buf, 32, h - 76, 22, (Color){ 250, 232, 200, 255 });
    text("ЛКМ — действие   ПКМ — обзор   G — готовая печка   Del — снести", 32, h - 46, 18, (Color){ 214, 196, 168, 255 });

    const char *names[] = { "Q  Рука", "1  Кирпич", "2  Цемент", "3  Опилки", "4  Спичка", "5  Труба", "6  Подпорка" };
    for (int i = 0; i < TOOL_COUNT; i++) {
        Color bg = (i == (int)tool) ? (Color){ 186, 108, 40, 230 } : (Color){ 16, 10, 8, 200 };
        DrawRectangle(w - 214, 18 + i * 46, 196, 40, bg);
        if (i == (int)tool) DrawRectangle(w - 214, 18 + i * 46, 5, 40, (Color){ 255, 210, 140, 255 });
        text(names[i], (float)(w - 198), 26 + i * 46.0f, 22, RAYWHITE);
    }
}

int main(void) {
    SetConfigFlags(FLAG_MSAA_4X_HINT | FLAG_WINDOW_RESIZABLE | FLAG_VSYNC_HINT);
    InitWindow(1440, 900, "Pechka 3D");
    SetTargetFPS(60);
    DisableCursor();

    setupGfx();

    int locSunDir = GetShaderLocation(shader, "sunDir");
    int locSunCol = GetShaderLocation(shader, "sunColor");
    Vector3 sunDir = Vector3Normalize((Vector3){ -0.35f, -1.0f, 0.55f });
    Vector3 sunCol = { 1.25f, 1.12f, 0.92f };
    SetShaderValue(shader, locSunDir, &sunDir, SHADER_UNIFORM_VEC3);
    SetShaderValue(shader, locSunCol, &sunCol, SHADER_UNIFORM_VEC3);
    float zero = 0;
    Vector3 z3 = { 0, 0.4f, 0 };
    SetShaderValue(shader, GetShaderLocation(shader, "firePos"), &z3, SHADER_UNIFORM_VEC3);
    SetShaderValue(shader, GetShaderLocation(shader, "firePower"), &zero, SHADER_UNIFORM_FLOAT);

    Camera3D cam = { 0 };
    cam.up = (Vector3){ 0, 1, 0 };
    cam.fovy = 52.0f;
    cam.projection = CAMERA_PERSPECTIVE;

    while (!WindowShouldClose()) {
        float dt = GetFrameTime();
        if (dt > 0.033f) dt = 0.033f;

        if (IsKeyPressed(KEY_Q)) tool = TOOL_HAND;
        if (IsKeyPressed(KEY_ONE)) tool = TOOL_BRICK;
        if (IsKeyPressed(KEY_TWO)) tool = TOOL_CEMENT;
        if (IsKeyPressed(KEY_THREE)) tool = TOOL_SAWDUST;
        if (IsKeyPressed(KEY_FOUR)) tool = TOOL_MATCH;
        if (IsKeyPressed(KEY_FIVE)) tool = TOOL_PIPE;
        if (IsKeyPressed(KEY_SIX)) tool = TOOL_PROP;
        if (IsKeyPressed(KEY_T)) runningBond = !runningBond;
        if (IsKeyPressed(KEY_TAB)) {
            if (IsCursorHidden()) EnableCursor();
            else DisableCursor();
        }

        Vector2 md = GetMouseDelta();
        if (IsCursorHidden() || IsMouseButtonDown(MOUSE_BUTTON_RIGHT)) {
            camYaw -= md.x * 0.0035f;
            camPitch += md.y * 0.0035f;
            if (camPitch < 0.12f) camPitch = 0.12f;
            if (camPitch > 1.25f) camPitch = 1.25f;
        }
        camDist -= GetMouseWheelMove() * 0.45f;
        if (camDist < 2.4f) camDist = 2.4f;
        if (camDist > 14.0f) camDist = 14.0f;

        Vector3 forward = { sinf(camYaw), 0, cosf(camYaw) };
        Vector3 right = { cosf(camYaw), 0, -sinf(camYaw) };
        float sp = 4.2f * dt;
        if (IsKeyDown(KEY_W)) camTarget = Vector3Add(camTarget, Vector3Scale(forward, -sp));
        if (IsKeyDown(KEY_S)) camTarget = Vector3Add(camTarget, Vector3Scale(forward, sp));
        if (IsKeyDown(KEY_A)) camTarget = Vector3Add(camTarget, Vector3Scale(right, -sp));
        if (IsKeyDown(KEY_D)) camTarget = Vector3Add(camTarget, Vector3Scale(right, sp));

        cam.position = (Vector3){
            camTarget.x + sinf(camYaw) * cosf(camPitch) * camDist,
            camTarget.y + sinf(camPitch) * camDist + 0.6f,
            camTarget.z + cosf(camYaw) * cosf(camPitch) * camDist
        };
        cam.target = camTarget;
        SetShaderValue(shader, shader.locs[SHADER_LOC_VECTOR_VIEW], &cam.position, SHADER_UNIFORM_VEC3);

        Vector2 aimScreen = IsCursorHidden()
            ? (Vector2){ GetScreenWidth() * 0.5f, GetScreenHeight() * 0.5f }
            : GetMousePosition();
        Ray ray = GetScreenToWorldRay(aimScreen, cam);
        RayCollision floor = groundHit(ray);
        Vector3 aim = floor.hit ? floor.point : camTarget;
        int hover = pickBody(ray);

        if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
            if (tool == TOOL_BRICK && floor.hit) {
                spawnBody(KIND_BRICK, snapPoint(aim), (Vector3){ 0, 0, 0 });
                burst(snapPoint(aim), (Color){ 180, 70, 40, 255 }, 6, 0);
            } else if (tool == TOOL_PIPE && floor.hit) {
                Vector3 p = snapPoint(aim);
                p.y += (PIPE_Y - BRICK_Y) * 0.5f;
                spawnBody(KIND_PIPE, p, (Vector3){ 0, 0, 0 });
            } else if (tool == TOOL_PROP && floor.hit) {
                Vector3 p = snapPoint(aim);
                p.y = 0.10f + PROP_Y * 0.5f;
                spawnBody(KIND_PROP, p, (Vector3){ 0, 0, 0 });
            } else if (tool == TOOL_CEMENT) {
                cementAt(hover >= 0 ? bodies[hover].pos : aim);
            } else if (tool == TOOL_MATCH) {
                igniteNear(hover >= 0 ? bodies[hover].pos : aim, 0.22f);
            } else if (tool == TOOL_SAWDUST) {
                pourDust(hover >= 0 ? bodies[hover].pos : (floor.hit ? aim : camTarget));
            }
        }
        static float pourAcc = 0;
        if (tool == TOOL_SAWDUST && IsMouseButtonDown(MOUSE_BUTTON_LEFT)) {
            pourAcc += dt;
            if (pourAcc > 0.12f) {
                pourAcc = 0;
                if (floor.hit) pourDust(aim);
            }
        } else {
            pourAcc = 0;
        }
        if (IsKeyPressed(KEY_G) && floor.hit) placeStove(snapPoint(aim));
        if (IsKeyPressed(KEY_DELETE)) {
            bodyCount = 0;
            weldCount = 0;
            partCount = 0;
            stoveTemp = 20;
        }

        updatePhysics(dt);
        updateFire(dt);

        BeginDrawing();
        ClearBackground((Color){ 142, 186, 226, 255 });
        BeginMode3D(cam);
        drawWorkshop();

        for (int i = 0; i < bodyCount; i++) if (bodies[i].alive) {
            Body *b = &bodies[i];
            Texture2D tex = texBrick;
            Color tint = WHITE;
            if (b->kind == KIND_PIPE) tex = texMetal;
            if (b->kind == KIND_PROP) tex = texWood;
            if (b->kind == KIND_DUST) { tex = texWood; tint = (Color){ 210, 176, 110, 255 }; }
            if (b->kind == KIND_ASH) { tex = texGround; tint = (Color){ 70, 66, 60, 255 }; }
            if (b->burning) tint = (Color){ 255, 120, 40, 255 };
            drawBox(b->pos, b->size, tex, tint);
            DrawCylinderEx(
                (Vector3){ b->pos.x, 0.101f, b->pos.z },
                (Vector3){ b->pos.x, 0.103f, b->pos.z },
                b->size.x * 0.55f, b->size.z * 0.42f, 8,
                (Color){ 0, 0, 0, 70 }
            );
            if (b->burning) {
                Vector3 fp = { b->pos.x, b->pos.y + b->size.y * 0.55f, b->pos.z };
                BeginBlendMode(BLEND_ADDITIVE);
                DrawSphere(fp, 0.07f, (Color){ 255, 230, 140, 220 });
                DrawSphere(fp, 0.14f, (Color){ 255, 120, 30, 90 });
                DrawSphere(fp, 0.22f, (Color){ 255, 70, 10, 40 });
                EndBlendMode();
            }
        }

        if (floor.hit && (tool == TOOL_BRICK || tool == TOOL_PIPE || tool == TOOL_PROP)) {
            Vector3 gpos = snapPoint(aim);
            Vector3 gs = kindSize(tool == TOOL_PIPE ? KIND_PIPE : tool == TOOL_PROP ? KIND_PROP : KIND_BRICK);
            if (tool == TOOL_PIPE) gpos.y += (PIPE_Y - BRICK_Y) * 0.5f;
            if (tool == TOOL_PROP) gpos.y = 0.10f + PROP_Y * 0.5f;
            DrawCubeWires(gpos, gs.x, gs.y, gs.z, (Color){ 255, 220, 140, 180 });
        }

        for (int i = 0; i < partCount; i++) {
            Part *p = &parts[i];
            Color c = p->color;
            c.a = (unsigned char)(255 * fminf(1.0f, p->life));
            DrawSphere(p->pos, p->size, c);
        }

        EndMode3D();
        DrawRectangleGradientV(0, 0, GetScreenWidth(), 90, (Color){ 20, 12, 8, 40 }, (Color){ 20, 12, 8, 0 });
        if (IsCursorHidden()) {
            int cx = GetScreenWidth() / 2;
            int cy = GetScreenHeight() / 2;
            DrawLine(cx - 10, cy, cx + 10, cy, (Color){ 255, 220, 160, 220 });
            DrawLine(cx, cy - 10, cx, cy + 10, (Color){ 255, 220, 160, 220 });
        }
        drawHud(GetScreenWidth(), GetScreenHeight());
        EndDrawing();
    }

    UnloadFont(font);
    UnloadMesh(meshBox);
    UnloadMesh(meshFloor);
    UnloadMesh(meshGrass);
    UnloadShader(shader);
    UnloadTexture(texBrick);
    UnloadTexture(texWood);
    UnloadTexture(texMetal);
    UnloadTexture(texGround);
    UnloadTexture(texWall);
    UnloadTexture(texGrass);
    UnloadTexture(texWhite);
    CloseWindow();
    return 0;
}
