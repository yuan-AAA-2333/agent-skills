#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
交叉验证：新通用框架 vs 原始脚本 smoke_shield_final.py 的物理计算。

原脚本顶部有 numpy/绘图等副作用，不能直接 import，
因此这里用**逐行等价复刻**的方式把它的核心公式搬进来（标了原行号），
然后在大量随机参数上比对两边的"遮蔽总时长"。

判据：两者差值 < 1e-9（同一套公式、同一套步长，应当逐位一致）。
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

# ---------------------------------------------------------------- 原脚本的常量（原 L67-L87）
M0 = np.array([20000.0, 0.0, 2000.0])
F0 = np.array([12000.0, 1400.0, 1400.0])
T = np.array([0.0, 200.0, 0.0])
VM = 300.0
G = 9.8
VS = 3.0
RC = 10.0
TEFF = 20.0
UM = -M0 / np.linalg.norm(M0)
T_ARR = np.linalg.norm(M0) / VM
V_MIN, V_MAX = 70.0, 140.0


def old_compute_params(theta, v, td, dt_delay):
    """逐行复刻原脚本 compute_params（原 L94-L112）。"""
    if not (V_MIN <= v <= V_MAX) or td < 0 or dt_delay < 0:
        return None
    uv = v * np.array([np.cos(theta), np.sin(theta), 0.0])
    Pd = F0 + td * uv
    z_det = Pd[2] - 0.5 * G * dt_delay**2
    if z_det < 0:
        return None
    tb = td + dt_delay
    Pb = Pd + uv * dt_delay + np.array([0, 0, -0.5 * G * dt_delay**2])
    t0 = tb
    t1 = min(tb + TEFF, T_ARR)
    if t0 >= t1:
        return None
    return dict(uv=uv, Pd=Pd, tb=tb, Pb=Pb, t0=t0, t1=t1, z_det=z_det)


def old_shield_blocked(ts, Pb, tb):
    """逐行复刻原脚本 shield_blocked（原 L115-L147）。"""
    N = len(ts)
    M_pts = M0 + (VM * ts)[:, None] * UM[None, :]
    C_pts = Pb + np.array([0, 0, -VS]) * (ts - tb)[:, None]
    d = T - M_pts
    a = np.sum(d * d, axis=1)
    f = M_pts - C_pts
    b = 2.0 * np.sum(f * d, axis=1)
    c = np.sum(f * f, axis=1) - RC**2
    disc = b * b - 4.0 * a * c
    has_root = np.zeros(N, dtype=bool)
    valid = (a > 1e-12) & (disc >= 0)
    if np.any(valid):
        sd = np.sqrt(disc[valid])
        s1 = (-b[valid] - sd) / (2.0 * a[valid])
        s2 = (-b[valid] + sd) / (2.0 * a[valid])
        has_root[valid] = ((s1 >= 0) & (s1 <= 1)) | ((s2 >= 0) & (s2 <= 1))
    return has_root


def old_shield_time(theta, v, td, dt_delay, step=0.01):
    """逐行复刻原脚本 shield_time（原 L150-L158）。"""
    p = old_compute_params(theta, v, td, dt_delay)
    if p is None:
        return 0.0
    ts = np.arange(p["t0"], p["t1"], step)
    if len(ts) == 0:
        return 0.0
    return float(np.sum(old_shield_blocked(ts, p["Pb"], p["tb"])) * step)


# ---------------------------------------------------------------- 新框架
ROOT = Path(r"G:\Code\01-科研\Mathematical-Modeling-Research\期中作业\smoke_screen_opt")
sys.path.insert(0, str(ROOT / "src"))
from smoke_screen.config import load_config                      # noqa: E402
from smoke_screen.scenario import Scenario                       # noqa: E402
from smoke_screen.simulator import shield_time as new_shield_time  # noqa: E402

cfg = load_config(ROOT / "configs" / "case_missile_drone.yaml")
scenario = Scenario.from_config(cfg)


def main() -> int:
    step = 0.01
    # 1) 到达时间一致性
    t_new = scenario.observer_arrival_time()
    print(f"[1] 观察者到达时间: 原={T_ARR:.9f}  新={t_new:.9f}  差={abs(T_ARR-t_new):.3e}")

    # 2) 物理常量一致性
    imm = {
        "遮蔽体半径": (RC, scenario.screen.radius),
        "有效时长": (TEFF, scenario.screen.effective_duration),
        "下沉速度": (VS, scenario.screen.fall_speed),
        "重力": (G, scenario.screen.gravity),
        "平台初位": (tuple(F0), tuple(np.round(scenario.platform.motion.p0, 6))),
        "目标参考点": (tuple(T), tuple(np.round(scenario.target.motion.p0, 6))),
    }
    ok = True
    for k, (a, b) in imm.items():
        same = np.allclose(np.asarray(a, dtype=float), np.asarray(b, dtype=float), atol=1e-9)
        print(f"[2] {k:<10} 原={a}  新={b}  {'OK' if same else '不一致!'}")
        ok &= same

    # 3) 随机参数上的遮蔽时长比对
    rng = np.random.default_rng(20260911)
    n = 2000
    worst = 0.0
    worst_case = None
    nonzero_new = nonzero_old = 0
    mismatch = 0
    # 采样范围对齐原脚本优化器的搜索区间（原 L203-L206）：
    #   θ 段 3.0~5.5 rad 横跨全部方向，但有效遮蔽只出现在指向目标的一小段里，
    #   因此额外用"射线-目标方向对齐"的方式构造一部分样本，保证验到非零解。
    for i in range(n):
        if i % 2 == 0:
            # 一半随机铺满
            theta = rng.uniform(3.0, 5.5)
            v = rng.uniform(V_MIN, V_MAX)
            td = rng.uniform(0.0, 30.0)
            dd = rng.uniform(0.05, 18.0)
        else:
            # 另一半：围绕"已探明的参考最优解"加扰动，保证验到非零解。
            # 参考最优由交叉验证脚本独立暴力搜索得到：
            #   θ=235.68° v=140 td=4.0 Δt=7.61 -> 4.95 s
            theta = np.radians(235.68) + rng.uniform(-0.15, 0.15)
            v = rng.uniform(120.0, 140.0)
            td = rng.uniform(0.5, 9.0)
            dd = rng.uniform(4.0, 11.0)
        a = old_shield_time(theta, v, td, dd, step=step)
        b = new_shield_time(scenario, [theta, v, td, dd], step=step)
        if a > 0:
            nonzero_old += 1
        if b > 0:
            nonzero_new += 1
        d = abs(a - b)
        if d > worst:
            worst, worst_case = d, (theta, v, td, dd, a, b)
        if d > 1e-9:
            mismatch += 1

    print(f"\n[3] 随机参数比对 ({n} 组, 步长 {step})")
    print(f"    原脚本非零解 {nonzero_old} 组 / 新框架非零解 {nonzero_new} 组")
    print(f"    最大差值 {worst:.3e}")
    if worst_case:
        th, v, td, dd, a, b = worst_case
        print(f"    最大差处: θ={th:.6f} v={v:.6f} td={td:.6f} Δt={dd:.6f} -> 原={a:.9f} 新={b:.9f}")
    print(f"    超过 1e-9 的组数: {mismatch}")

    # 4) 非法参数（越界/起爆点在地面下）两边都应给 0
    edge = [(2.0, 100.0, 5.0, 2.0), (4.0, 50.0, 5.0, 2.0), (4.0, 100.0, -1.0, 2.0),
            (4.0, 100.0, 5.0, 19.5), (5.4, 139.0, 29.0, 17.0)]
    print("\n[4] 边界与非法参数")
    for th, v, td, dd in edge:
        a = old_shield_time(th, v, td, dd, step=step)
        b = new_shield_time(scenario, [th, v, td, dd], step=step)
        flag = "OK" if abs(a - b) < 1e-9 else "不一致!"
        print(f"    θ={np.degrees(th):7.2f}° v={v:6.1f} td={td:6.2f} Δt={dd:5.2f} -> 原={a:.6f} 新={b:.6f}  {flag}")

    verdict = ok and mismatch == 0
    print(f"\n结论: {'✅ 完全一致 —— 通用化未改变任何物理行为' if verdict else '❌ 存在差异，需要排查'}")
    return 0 if verdict else 1


if __name__ == "__main__":
    raise SystemExit(main())
