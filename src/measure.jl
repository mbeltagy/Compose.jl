using Measures: Add, Min, Max, Div, Mul, Neg

# Measure Constants
# -----------------

const cx = Length{:cx}
const cy = Length{:cy}

*{T}(a::T, b::Type{cx}) = x_measure(a)
*{T}(a::T, b::Type{cy}) = y_measure(a)

# Pixels are not typically used in Compose in preference of absolute
# measurements or measurements relative to parent canvases. So for the
# 'px' constant, we just punt and give something do something vaguely
# reasonable.

const assumed_ppmm = 3.78 # equivalent to 96 DPI
const px = mm/assumed_ppmm

const MeasureOrNumber = Union{Measure, Number}
const XYTupleOrVec = Union{Tuple{MeasureOrNumber,MeasureOrNumber}, Vec}


# Scaling w and h components
# --------------------------

# Compute the length of the given type.
sum_component{T <: Length}(::Type{T}, l) = 0.0
sum_component{T <: Length}(::Type{T}, l::T) = l.value
sum_component{T <: Length}(::Type{T}, l::Add) = sum_component(T, l.a) + sum_component(T, l.b)

# Scale a length component by some factor.
scale_component{T <: Length}(::Type{T}, scale, l) = l
scale_component{T <: Length}(::Type{T}, scale, l::T) = T(scale * l.value)
scale_component{T <: Length}(::Type{T}, scale, l::Add) =
        scale_component(T, scale, l.a) + scale_component(T, scale, l.b)


# Interpretation of bare numbers
# ------------------------------

x_measure(a::Measure) = a
x_measure{T}(a::T) = Length{:cx, T}(a)

y_measure(a::Measure) = a
y_measure{T}(a::T) = Length{:cy, T}(a)

x_measure{T<:Measure}(a::Vector{T}) = a
x_measure(a::Vector) = Measure[x_measure(x) for x in a]

y_measure{T<:Measure}(a::Vector{T}) = a
y_measure(a::Vector) = Measure[y_measure(y) for y in a]

size_measure(a::Measure) = a
size_measure(a) = a * mm


# Higher-order measures
# ---------------------

# Compute the union of two bounding boxes.
#
# In other words, given two bounding boxes, return a new bounding box that
# contains both.
#
# Unfortunately this is in general uncomputable without knowing the absolute
# size of the parent canvas which may be passed in via the last two parameters.
# If not passed, this throws an error if they would have been required.
#
function union(a::BoundingBox, b::BoundingBox, units=nothing, parent_abs_width=nothing, parent_abs_height=nothing)
    (a.width == Measure() || a.height == Measure()) && return b
    (b.width == Measure() || b.height == Measure()) && return a
    x0 = min(a.x0, b.x0)
    y0 = min(a.y0, b.y0)
    x1 = max(a.x0 + a.width, b.x0 + b.width)
    y1 = max(a.y0 + a.height, b.y0 + b.height)
    # Check whether we had any problematic computations
    for m in (x0,y0,x1,y1)
        # Pure absolute or pure relative points are fine. When they are mixed,
        # there are problems
        if !isabsolute(m) && m.abs != 0.0
            units == nothing || parent_abs_width == nothing || parent_abs_height == nothing &&
                    error("""Bounding boxes are uncomputable without knowledge of the
                        absolute dimensions of the top canvase due to mixing of relative
                        and absolute coordinates. Either pass the dimension as a parameter
                        or restrict the context to one kind of coordinates.""")
            parent_box = AbsoluteBox(0.0,0.0,parent_abs_width,parent_abs_height)
            abb = union(absolute_units(a,IdentityTransform(),units,parent_box),
                        absolute_units(b,IdentityTransform(),units,parent_box))
            return BoundingBox(Measure(;abs = abb.x0), Measure(;abs = abb.x0),
                               Measure(;abs = abb.width), Measure(;abs = abb.height))
        end
    end
    return BoundingBox(x0, y0, x1 - x0, y1 - y0)
end

function union(a::AbsoluteBox, b::AbsoluteBox)
    (a.width == 0.0 || a.height == 0.0) && return b
    (b.width == 0.0 || b.height == 0.0) && return a
    x0 = min(a.x0, b.x0)
    y0 = min(a.y0, b.y0)
    x1 = max(a.x0 + a.width, b.x0 + b.width)
    y1 = max(a.y0 + a.height, b.y0 + b.height)
    return AbsoluteBox(x0, y0, x1 - x0, y1 - y0)
end

# The same type-signature is used for a box used to assign
# a custom coordinate system to a canvas.

immutable UnitBox{S,T,U,V}
    x0::S
    y0::T
    width::U
    height::V

    leftpad::AbsoluteLength
    rightpad::AbsoluteLength
    toppad::AbsoluteLength
    bottompad::AbsoluteLength
end

UnitBox(x0, y0, width, height; leftpad=0mm, rightpad=0mm, toppad=0mm, bottompad=0mm) =
        UnitBox{typeof(x0), typeof(y0), typeof(width), typeof(height)}(
            x0, y0, width, height, leftpad, rightpad, toppad, bottompad)

function UnitBox(width, height; leftpad=0mm, rightpad=0mm, toppad=0mm, bottompad=0mm)
    S, T = typeof(width), typeof(height)
    UnitBox{S,T,S,T}(zero(S), zero(T), width, height, leftpad, rightpad, toppad, bottompad)
end

UnitBox() = UnitBox(0.0, 0.0, 1.0, 1.0)

const NullUnitBox = Nullable{UnitBox}

# copy with substitution
UnitBox(units::UnitBox;
                 x0=Nullable{Measure}(),
                 y0=Nullable{Measure}(),
                 width=Nullable{Measure}(),
                 height=Nullable{Measure}(),
                 leftpad=Nullable{AbsoluteLength}(),
                 rightpad=Nullable{AbsoluteLength}(),
                 toppad=Nullable{AbsoluteLength}(),
                 bottompad=Nullable{AbsoluteLength}()) =
        UnitBox(ifelse(isa(x0, Nullable)     && isnull(x0),     units.x0,     x0),
            ifelse(isa(y0, Nullable)     && isnull(y0),     units.y0,     y0),
            ifelse(isa(width, Nullable)  && isnull(width),  units.width,  width),
            ifelse(isa(height, Nullable) && isnull(height), units.height, height),
            leftpad   = ifelse(isa(leftpad,   Nullable) && isnull(leftpad),   units.leftpad,   leftpad),
            rightpad  = ifelse(isa(rightpad,  Nullable) && isnull(rightpad),  units.rightpad,  rightpad),
            toppad    = ifelse(isa(toppad,    Nullable) && isnull(toppad),    units.toppad,    toppad),
            bottompad = ifelse(isa(bottompad, Nullable) && isnull(bottompad), units.bottompad, bottompad))

Measures.width(units::UnitBox) = units.width
Measures.height(units::UnitBox) = units.height

ispadded(units::UnitBox) = units.leftpad != 0mm || units.rightpad != 0mm ||
        units.toppad != 0mm || units.bottompad != 0mm

isxflipped{S, T, U, V}(units::UnitBox{S, T, U, V}) = units.width < zero(U)
isyflipped{S, T, U, V}(units::UnitBox{S, T, U, V}) = units.height < zero(V)
hasunits(::Type, x::Measure) = false
hasunits{u, T}(::Type{Length{u}}, x::Length{u, T}) = true
hasunits(T::Type, x::Measures.BinaryOp) = hasunits(T, x.a) || hasunits(T, x.b)


# Canvas Transforms
# -----------------

# Transform matrix in absolute coordinates

@compat abstract type Transform end

immutable IdentityTransform <: Transform
end

immutable MatrixTransform <: Transform
    M::Matrix{Float64}
end

combine(a::IdentityTransform, b::IdentityTransform) = a
combine(a::IdentityTransform, b::MatrixTransform) = b
combine(a::MatrixTransform, b::IdentityTransform) = a
combine(a::MatrixTransform, b::MatrixTransform) = MatrixTransform(a.M * b.M)

# Rotation about a point.
immutable Rotation{P <: Vec}
    theta::Float64
    offset::P
end

Rotation(theta::Number, offset::XYTupleOrVec) =
        Rotation(convert(Float64, theta), (x_measure(offset[1]), y_measure(offset[2])))
Rotation(theta::Number, offset_x, offset_y) =
        Rotation(convert(Float64, theta), (x_measure(offset_x), y_measure(offset_y)))
Rotation(theta::Number) = Rotation{Vec2}(convert(Float64, theta), (0.5w, 0.5h))
Rotation() = Rotation(0.0, (0.5w, 0.5h))

copy(rot::Rotation) = Rotation(rot)

function convert(::Type{Transform}, rot::Rotation)
    if rot.theta == 0.0
        return IdentityTransform()
    else
        ct = cos(rot.theta)
        st = sin(rot.theta)
        x0 = rot.offset[1] - (ct * rot.offset[1] - st * rot.offset[2])
        y0 = rot.offset[2] - (st * rot.offset[1] + ct * rot.offset[2])
        return MatrixTransform([ct  -st  x0.value
                                st   ct  y0.value
                                0.0 0.0  1.0])
    end
end

# Mirror about a point at a given angle
type Mirror
    theta::Float64
    point::Vec
end

Mirror(theta::Number, offset_x, offset_y) = Mirror(convert(Float64, theta), (offset_x, offset_y))
Mirror(theta::Number, offset::XYTupleOrVec) =
        Mirror(convert(Float64, theta), (x_measure(offset[1]), y_measure(offset[2])))
Mirror(theta::Number) = Mirror(convert(Float64, theta), 0.5w, 0.5h)
Mirror() = Mirror(0.0, (0.5w, 0.5h))

# copy constructor
Mirror(mir::Mirror) = Mirror(copy(mir.theta), copy(mir.offset))

function convert(::Type{Transform}, mir::Mirror)
    n = [cos(mir.theta), sin(mir.theta)]
    x0 = mir.point[1]
    y0 = mir.point[2]

    offset = (2I - 2n*n') * [x0.abs, y0.abs]
    scale  = (2n*n' - I)
    M = vcat(hcat(scale, offset), [0 0 1])

    MatrixTransform(M)
end

copy(mir::Mirror) = Mirror(mir)


# Resolution
# ----------

resolve(box::AbsoluteBox, units::UnitBox, t::Transform, a::Length) = resolve(box, a)
resolve_position(box::AbsoluteBox, units::UnitBox, t::Transform, a::Length{:cx}) =
        ((a.value - units.x0) / width(units)) * box.a[1]
resolve(box::AbsoluteBox, units::UnitBox, t::Transform, a::Length{:cx}) =
        abs(a.value / width(units)) * box.a[1]
resolve_position(box::AbsoluteBox, units::UnitBox, t::Transform, a::Length{:cy}) =
        ((a.value - units.y0) / height(units)) * box.a[2]
resolve(box::AbsoluteBox, units::UnitBox, t::Transform, a::Length{:cy}) =
        abs(a.value / height(units)) * box.a[2]

function resolve(box::AbsoluteBox, units::UnitBox, t::Transform, p::Vec2)
    xy = (resolve_position(box, units, t, p[1]) + box.x0[1],
          resolve_position(box, units, t, p[2]) + box.x0[2])
    return xy
end

function resolve(box::AbsoluteBox, units::UnitBox, t::MatrixTransform, p::Vec2)
    x = resolve_position(box, units, t, p[1]) + box.x0[1]
    y = resolve_position(box, units, t, p[2]) + box.x0[2]
    xy = t.M * [x.value, y.value, 1]
    return (xy[1]mm, xy[2]mm)
end

resolve(box::AbsoluteBox, units::UnitBox, t::Transform, a::BoundingBox) =
        BoundingBox(resolve(box, units, t, a.x0),
            (resolve(box, units, t, a.a[1]), resolve(box, units, t, a.a[2])))

resolve(box::AbsoluteBox, units::UnitBox, t::Transform, a::Rotation) =
        Rotation(a.theta, resolve(box, units, t, a.offset))

function resolve(box::AbsoluteBox, units::UnitBox, t::Transform, u::UnitBox)
    if !ispadded(u)
        return u
    else
        leftpad   = resolve(box, units, t, u.leftpad)
        rightpad  = resolve(box, units, t, u.rightpad)
        toppad    = resolve(box, units, t, u.toppad)
        bottompad = resolve(box, units, t, u.bottompad)

        # just give up trying to pad the units if it's impossible
        if leftpad + rightpad >= box.a[1] ||
           toppad + bottompad >= box.a[2]
            return UnitBox(u.x0, u.y0, u.width, u.height)
        end

        width = u.width * (box.a[1] / (box.a[1] - leftpad - rightpad))
        height = u.height * (box.a[2] / (box.a[2] - toppad - bottompad))
        x0 = u.x0 - width * (leftpad / box.a[1])
        y0 = u.y0 - height * (toppad / box.a[2])

        return UnitBox(x0, y0, width, height)
    end
end

# Equivalent to the resolve functions in Measures, but pass through the `units`
# and `transform` parameters.
resolve(box::AbsoluteBox, units::UnitBox, t::Transform, x::Neg) =
        -resolve(box, units, t, x.a)
resolve(box::AbsoluteBox, units::UnitBox, t::Transform, x::Add) =
        resolve(box, units, t, x.a) + resolve(box, units, t, x.b)
resolve(box::AbsoluteBox, units::UnitBox, t::Transform, x::Mul) =
        resolve(box, units, t, x.a) * x.b
resolve(box::AbsoluteBox, units::UnitBox, t::Transform, x::Div) =
        resolve(box, units, t, x.a) / x.b
resolve(box::AbsoluteBox, units::UnitBox, t::Transform, x::Min) =
        min(resolve(box, units, t, x.a), resolve(box, units, t, x.b))
resolve(box::AbsoluteBox, units::UnitBox, t::Transform, x::Max) =
        max(resolve(box, units, t, x.a), resolve(box, units, t, x.b))

resolve_position(box::AbsoluteBox, units::UnitBox, t::Transform, a) = resolve(box, units, t, a)
resolve_position(box::AbsoluteBox, units::UnitBox, t::Transform, op::Add) =
        resolve_position(box, units, t, op.a) + resolve_position(box, units, t, op.b)
