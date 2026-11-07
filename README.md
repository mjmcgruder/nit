# nit

## Why?

A few years ago I saw Nathan Reed's blog post 'Reading Veach's Thesis' and thought that understanding the methods would be cool one day. I'm nowhere near understanding Veach's thesis yet but I know more Monte Carlo than ever and I'm having fun.

## Building

This code requires Zig 0.17.*.

```
zig build -Doptimize=fast
```

## Testing

Tests are discovered recursively through the primary target module.

```
zig test nit.zig
```

## References

- [Physically Based Rendering, From Theory to Implementation](https://www.pbrt.org/) by Matt Pharr, Wenzel Jakob, and Greg Humphreys. My physical copy is excellent.
- [How to build a BVH](https://jacco.ompf2.com/2022/04/13/how-to-build-a-bvh-part-1-basics/) by Jacco Bikker.
- [Ray-Surface intersection functions](https://iquilezles.org/articles/intersectors/) by Inigo Quilez.
- [Reading Veach's Thesis](https://www.reedbeta.com/blog/reading-veach-thesis/) by Nathan Reed.
- [smallpt](https://kevinbeason.com/smallpt/) by Kevin Beason.
- [meshoptimizer](https://github.com/zeux/meshoptimizer) by Arseny Kapoulkine.
- Optimally Combining Sampling Techniques for Monte Carlo Rendering, Eric Veach and Leonidas J. Guibas.
- Robust Monte Carlo Methods for Light Transport Simulation, Eric Veach

## Status and Radmap

The current path tracing implementation is simple next event estimation. The light transport equation is split into direct and indirect components, each is estimated separately, and the estimates are summed. The directional form of the light transport equation is used. Variance is high in the presence of specular reflection as expected.

to learn list:
- glossy reflection (mostly to test MIS properly)
- multiple importance sampling
- bi-directional methods
- metropolis light transport
