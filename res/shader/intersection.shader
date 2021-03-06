=type lib
=include math.shader

uniform samplerBuffer vertices;
uniform samplerBuffer normals;
uniform samplerBuffer texCoords;
uniform isamplerBuffer indices;
uniform samplerBuffer bounds;
uniform isamplerBuffer matIndices;
uniform isamplerBuffer hitTable;
uniform int bvhSize;
uniform int objPrimCount;

struct Ray
{
	vec3 ori;
	vec3 dir;
};

struct SurfaceInfo
{
	vec3 norm;
	vec2 texCoord;
};

struct SurfaceInteraction
{
	vec3 Wo;
	vec3 Wi;
	vec3 N;
};

struct HitInfo
{
	bool hit;
	float dist;
};

vec3 rayPoint(Ray ray, float t)
{
	return ray.ori + ray.dir * t;
}

HitInfo intersectTriangle(vec3 a, vec3 b, vec3 c, Ray ray)
{
	HitInfo ret;
	const float eps = 1e-6;

	vec3 ab = b - a;
	vec3 ac = c - a;
	vec3 o = ray.ori;
	vec3 d = ray.dir;

	vec3 p = cross(d, ac);
	float det = dot(ab, p);

	if (abs(det) < eps)
	{
		ret.hit = false;
		return ret;
	}

	vec3 ao = o - a;
	if (det < 0)
	{
		ao = -ao;
		det = -det;
	}

	float u = dot(ao, p);
	if (u < 0.0 || u > det)
	{
		ret.hit = false;
		return ret;
	}

	vec3 q = cross(ao, ab);

	float v = dot(d, q);
	if (v < 0.0 || u + v > det)
	{
		ret.hit = false;
		return ret;
	}

	float t = dot(ac, q) / det;
	ret.hit = (t > 0.0);
	ret.dist = t;
	return ret;
}

HitInfo intersectTriangle(int id, Ray ray)
{
	int ia = texelFetch(indices, id * 3 + 0).r;
	int ib = texelFetch(indices, id * 3 + 1).r;
	int ic = texelFetch(indices, id * 3 + 2).r;

	vec3 a = texelFetch(vertices, ia).xyz;
	vec3 b = texelFetch(vertices, ib).xyz;
	vec3 c = texelFetch(vertices, ic).xyz;
	return intersectTriangle(a, b, c, ray);
}

vec3 triangleRandomPoint(int id, vec2 u)
{
	int ia = texelFetch(indices, id * 3 + 0).r;
	int ib = texelFetch(indices, id * 3 + 1).r;
	int ic = texelFetch(indices, id * 3 + 2).r;

	vec3 a = texelFetch(vertices, ia).xyz;
	vec3 b = texelFetch(vertices, ib).xyz;
	vec3 c = texelFetch(vertices, ic).xyz;

	return sampleTriangleUniform(a, b, c, u);
}

float triangleArea(int id)
{
	int ia = texelFetch(indices, id * 3 + 0).r;
	int ib = texelFetch(indices, id * 3 + 1).r;
	int ic = texelFetch(indices, id * 3 + 2).r;

	vec3 a = texelFetch(vertices, ia).xyz;
	vec3 b = texelFetch(vertices, ib).xyz;
	vec3 c = texelFetch(vertices, ic).xyz;

	return triangleArea(a, b, c);
}

SurfaceInfo triangleSurfaceInfo(int id, vec3 p)
{
	SurfaceInfo ret;

	int ia = texelFetch(indices, id * 3 + 0).r;
	int ib = texelFetch(indices, id * 3 + 1).r;
	int ic = texelFetch(indices, id * 3 + 2).r;

	vec3 a = texelFetch(vertices, ia).xyz;
	vec3 b = texelFetch(vertices, ib).xyz;
	vec3 c = texelFetch(vertices, ic).xyz;

	vec3 na = texelFetch(normals, ia).xyz;
	vec3 nb = texelFetch(normals, ib).xyz;
	vec3 nc = texelFetch(normals, ic).xyz;

	vec2 ta = texelFetch(texCoords, ia).xy;
	vec2 tb = texelFetch(texCoords, ib).xy;
	vec2 tc = texelFetch(texCoords, ic).xy;

	vec3 pa = a - p;
	vec3 pb = b - p;
	vec3 pc = c - p;

	float areaInv = 1.0 / length(cross(b - a, c - a));
	float la = length(cross(pb, pc)) * areaInv;
	float lb = length(cross(pc, pa)) * areaInv;
	float lc = 1.0 - la - lb;

	ret.norm = normalize(na * la + nb * lb + nc * lc);
	ret.texCoord = ta * la + tb * lb + tc * lc;

	return ret;
}

bool boxHit(int id, Ray ray, out float tMin)
{
	float tMax;
	vec3 pMin = texelFetch(bounds, id * 2 + 0).xyz;
	vec3 pMax = texelFetch(bounds, id * 2 + 1).xyz;

	const float eps = 1e-6;
	vec3 o = ray.ori;
	vec3 d = ray.dir;

	if (abs(d.x) > 1.0 - eps)
	{
		if (o.y > pMin.y && o.y < pMax.y && o.z > pMin.z && o.z < pMax.z)
		{
			float dxInv = 1.0 / d.x;
			float ta = (pMin.x - o.x) * dxInv;
			float tb = (pMax.x - o.x) * dxInv;
			tMin = min(ta, tb);
			tMax = max(ta, tb);
			return tMax >= 0.0 && tMax >= tMin;
		}
		else return false;
	}

	if (abs(d.y) > 1.0 - eps)
	{
		if (o.x > pMin.x && o.x < pMax.x && o.z > pMin.z && o.z < pMax.z)
		{
			float dyInv = 1.0 / d.y;
			float ta = (pMin.y - o.y) * dyInv;
			float tb = (pMax.y - o.y) * dyInv;
			tMin = min(ta, tb);
			tMax = max(ta, tb);
			return tMax >= 0.0 && tMax >= tMin;
		}
		else return false;
	}

	if (abs(d.z) > 1.0 - eps)
	{
		if (o.x > pMin.x && o.x < pMax.x && o.y > pMin.y && o.y < pMax.y)
		{
			float dzInv = 1.0 / d.z;
			float ta = (pMin.z - o.z) * dzInv;
			float tb = (pMax.z - o.z) * dzInv;
			tMin = min(ta, tb);
			tMax = max(ta, tb);
			return tMax >= 0.0 && tMax >= tMin;
		}
		else return false;
	}

	vec3 dInv = 1.0 / d;
	vec3 vta = (pMin - o) * dInv;
	vec3 vtb = (pMax - o) * dInv;

	vec3 vtMin = min(vta, vtb);
	vec3 vtMax = max(vta, vtb);

	vec3 dt = vtMax - vtMin;

	float tyz = vtMax.z - vtMin.y;
	float tzx = vtMax.x - vtMin.z;
	float txy = vtMax.y - vtMin.x;

	if (abs(d.x) < eps)
	{
		if (dt.y + dt.z > tyz)
		{
			tMin = max(vtMin.y, vtMin.z);
			tMax = min(vtMax.y, vtMax.z);
			return tMax >= 0.0 && tMax >= tMin;
		}
	}

	if (abs(d.y) < eps)
	{
		if (dt.z + dt.x > tzx)
		{
			tMin = max(vtMin.z, vtMin.x);
			tMax = min(vtMax.z, vtMax.x);
			return tMax >= 0.0 && tMax >= tMin;
		}
	}

	if (abs(d.z) < eps)
	{
		if (dt.x + dt.y > txy)
		{
			tMin = max(vtMin.x, vtMin.y);
			tMax = min(vtMax.x, vtMax.y);
			return tMax >= 0.0 && tMax >= tMin;
		}
	}

	if (dt.y + dt.z > tyz && dt.z + dt.x > tzx && dt.x + dt.y > txy)
	{
		tMin = max(max(vtMin.x, vtMin.y), vtMin.z);
		tMax = min(min(vtMax.x, vtMax.y), vtMax.z);
		return tMax >= 0.0 && tMax >= tMin;
	}

	return false;
}

float maxDepth = 0.0;

bool bvhTest(Ray ray, float dist)
{
	int tableOffset = cubemapFace(-ray.dir) * bvhSize;
	int k = 0;

	while (k != bvhSize)
	{
		int nodeIndex = texelFetch(hitTable, tableOffset + k).r;
		int primIndex = texelFetch(hitTable, tableOffset + k).g;

		float boxDist;
		bool bHit = boxHit(nodeIndex, ray, boxDist);
		if (!bHit || (bHit && boxDist > dist))
		{
			k = texelFetch(hitTable, tableOffset + k).b;
			continue;
		}

		if (primIndex >= 0)
		{
			HitInfo hInfo = intersectTriangle(primIndex, ray);
			if (hInfo.hit && hInfo.dist < dist) return true;
		}
		k++;
	}
	return false;
}

int bvhHit(Ray ray, out float dist)
{
	dist = 1e8;
	int closest = -1;
	int tableOffset = cubemapFace(-ray.dir) * bvhSize;

	int k = 0;
	while (k != bvhSize)
	{
		int nodeIndex = texelFetch(hitTable, tableOffset + k).r;
		int primIndex = texelFetch(hitTable, tableOffset + k).g;

		float boxDist;
		bool bHit = boxHit(nodeIndex, ray, boxDist);
		if (!bHit || (bHit && boxDist > dist))
		{
			k = texelFetch(hitTable, tableOffset + k).b;
			continue;
		}

		if (primIndex >= 0)
		{
			HitInfo hInfo = intersectTriangle(primIndex, ray);
			if (hInfo.hit && hInfo.dist < dist)
			{
				dist = hInfo.dist;
				closest = primIndex;
			}
		}
		k++;
		maxDepth += 1.0;
	}
	return closest;
}

struct SceneHitInfo
{
	int primId;
	float dist;
};

SceneHitInfo sceneHit(Ray ray)
{
	SceneHitInfo ret;
	ret.primId = bvhHit(ray, ret.dist);
	return ret;
}