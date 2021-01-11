# annotate types for geofacs + connectivity arrays for speed in RHS evals
struct MeshData{Dim, GeoType, IndexType, BdryIndexType}

    VXYZ::NTuple{Dim,T} where{T}  # vertex coordinates
    K::Int                       # num elems
    EToV                         # mesh vertex array
    FToF::IndexType                # face connectivity

    xyz::NTuple{Dim,GeoType}   # physical points
    xyzf::NTuple{Dim,GeoType}   # face nodes
    xyzq::NTuple{Dim,GeoType}  # phys quad points, Jacobian-scaled weights
    wJq::GeoType

    # arrays of connectivity indices between face nodes
    mapM::IndexType
    mapP::IndexType
    mapB::BdryIndexType

    # volume geofacs Gij = dx_i/dxhat_j
    rstxyzJ::SMatrix{Dim,Dim,GeoType,L} where {L}
    J::GeoType

    # surface geofacs
    nxyzJ::NTuple{Dim,GeoType}
    sJ::GeoType
end

# type alias for just dim/shape
const MeshData{Dim} = MeshData{Dim,GeoType,IndexType,BdryIndexType} where {GeoType,IndexType,BdryIndexType}

# convenience routines for unpacking individual tuple entries
function Base.getproperty(x::MeshData,s::Symbol)

    if s==:VX
        return getproperty(x, :VXYZ)[1]
    elseif s==:VY
        return getproperty(x, :VXYZ)[2]
    elseif s==:VZ
        return getproperty(x, :VXYZ)[3]

    elseif s==:x
        return getproperty(x, :xyz)[1]
    elseif s==:y
        return getproperty(x, :xyz)[2]
    elseif s==:z
        return getproperty(x, :xyz)[3]

    elseif s==:xq
        return getproperty(x, :xyzq)[1]
    elseif s==:yq
        return getproperty(x, :xyzq)[2]
    elseif s==:zq
        return getproperty(x, :xyzq)[3]

    elseif s==:xf
        return getproperty(x, :xyzf)[1]
    elseif s==:yf
        return getproperty(x, :xyzf)[2]
    elseif s==:zf
        return getproperty(x, :xyzf)[3]

    elseif s==:nxJ
        return getproperty(x, :nxyzJ)[1]
    elseif s==:nyJ
        return getproperty(x, :nxyzJ)[2]
    elseif s==:nzJ
        return getproperty(x, :nxyzJ)[3]

    elseif s==:rxJ
        return getproperty(x, :rstxyzJ)[1,1]
    elseif s==:sxJ
        return getproperty(x, :rstxyzJ)[1,2]
    elseif s==:txJ
        return getproperty(x, :rstxyzJ)[1,3]
    elseif s==:ryJ
        return getproperty(x, :rstxyzJ)[2,1]
    elseif s==:syJ
        return getproperty(x, :rstxyzJ)[2,2]
    elseif s==:tyJ
        return getproperty(x, :rstxyzJ)[2,3]
    elseif s==:rzJ
        return getproperty(x, :rstxyzJ)[3,1]
    elseif s==:szJ
        return getproperty(x, :rstxyzJ)[3,2]
    elseif s==:tzJ
        return getproperty(x, :rstxyzJ)[3,3]

    else
        return getfield(x,s)
    end
end

function MeshData(VX::AbstractArray,EToV,rd::RefElemData)

    # Construct global coordinates
    @unpack V1 = rd
    x = V1*VX[transpose(EToV)]
    K = size(EToV,1)
    Nfaces = 2

    FToF = zeros(Int,Nfaces,K)
    sk = 1
    for e = 1:K
        l = 2*e-1
        r = 2*e
        FToF[1:2,e] .= [l-1; r+1]
        sk += 1
    end
    FToF[1,1] = 1
    FToF[Nfaces,K] = Nfaces*K

    # Connectivity maps
    @unpack Vf = rd
    xf = Vf*x
    mapM = reshape(1:2*K,2,K)
    mapP = copy(mapM)
    mapP[1,2:end] .= mapM[2,1:end-1]
    mapP[2,1:end-1] .= mapM[1,2:end]
    mapB = findall(@. mapM[:]==mapP[:])

    # Geometric factors and surface normals
    J = repeat(transpose(diff(VX)/2),length(rd.r),1)
    rxJ = one.(J)
    nxJ = repeat([-1.0; 1.0],1,K)
    sJ = abs.(nxJ)

    @unpack Vq,wq = rd
    xq = Vq*x
    wJq = diagm(wq)*(Vq*J)

    return MeshData(tuple(VX),K,EToV,FToF,
                     tuple(x),tuple(xf),tuple(xq),wJq,
                     collect(mapM),mapP,mapB,
                     SMatrix{1,1}(tuple(rxJ)),J,
                     tuple(nxJ),sJ)

end

function MeshData(VX,VY,EToV,rd::RefElemData)

    @unpack fv = rd
    FToF = connect_mesh(EToV,fv)
    Nfaces,K = size(FToF)

    #Construct global coordinates
    @unpack V1 = rd
    x,y = V1*VX[transpose(EToV)], V1*VY[transpose(EToV)]

    #Compute connectivity maps: uP = exterior value used in DG numerical fluxes
    @unpack r,s,Vf = rd
    xf,yf = Vf*x, Vf*y
    mapM,mapP,mapB = build_node_maps(FToF,xf,yf)
    Nfp = convert(Int,size(Vf,1)/Nfaces)
    mapM = reshape(mapM,Nfp*Nfaces,K)
    mapP = reshape(mapP,Nfp*Nfaces,K)

    #Compute geometric factors and surface normals
    @unpack Dr,Ds = rd
    rxJ, sxJ, ryJ, syJ, J = geometric_factors(x, y, Dr, Ds)

    @unpack Vq,wq = rd
    xq,yq = (x->Vq*x).((x,y))
    wJq = diagm(wq)*(Vq*J)

    #physical normals are computed via G*nhatJ, G = matrix of geometric terms
    @unpack nrJ,nsJ = rd
    nxJ = (Vf*rxJ).*nrJ + (Vf*sxJ).*nsJ
    nyJ = (Vf*ryJ).*nrJ + (Vf*syJ).*nsJ
    sJ = @. sqrt(nxJ^2 + nyJ^2)

    return MeshData(tuple(VX,VY),K,EToV,FToF,
                     tuple(x,y),tuple(xf,yf),tuple(xq,yq),wJq,
                     mapM,mapP,mapB,
                     SMatrix{2,2}(tuple(rxJ,ryJ,sxJ,syJ)),J,
                     tuple(nxJ,nyJ),sJ)

end


function MeshData(VX,VY,VZ,EToV,rd::RefElemData)

    @unpack fv = rd
    FToF = connect_mesh(EToV,fv)
    Nfaces,K = size(FToF)

    #Construct global coordinates
    @unpack V1 = rd
    x,y,z = (x->V1*x[transpose(EToV)]).((VX,VY,VZ))

    #Compute connectivity maps: uP = exterior value used in DG numerical fluxes
    @unpack r,s,t,Vf = rd
    xf,yf,zf = (x->Vf*x).((x,y,z))
    mapM,mapP,mapB = build_node_maps(FToF,xf,yf,zf)
    Nfp = convert(Int,size(Vf,1)/Nfaces)
    mapM = reshape(mapM,Nfp*Nfaces,K)
    mapP = reshape(mapP,Nfp*Nfaces,K)

    #Compute geometric factors and surface normals
    @unpack Dr,Ds,Dt = rd
    rxJ,sxJ,txJ,ryJ,syJ,tyJ,rzJ,szJ,tzJ,J = geometric_factors(x,y,z,Dr,Ds,Dt)

    @unpack Vq,wq = rd
    xq,yq,zq = (x->Vq*x).((x,y,z))
    wJq = diagm(wq)*(Vq*J)

    #physical normals are computed via G*nhatJ, G = matrix of geometric terms
    @unpack nrJ,nsJ,ntJ = rd
    nxJ = nrJ.*(Vf*rxJ) + nsJ.*(Vf*sxJ) + ntJ.*(Vf*txJ)
    nyJ = nrJ.*(Vf*ryJ) + nsJ.*(Vf*syJ) + ntJ.*(Vf*tyJ)
    nzJ = nrJ.*(Vf*rzJ) + nsJ.*(Vf*szJ) + ntJ.*(Vf*tzJ)
    sJ = @. sqrt(nxJ.^2 + nyJ.^2 + nzJ.^2)

    return MeshData(tuple(VX,VY,VZ),K,EToV,FToF,
                     tuple(x,y,z),tuple(xf,yf,zf),tuple(xq,yq,zq),wJq,
                     mapM,mapP,mapB,
                     SMatrix{3,3}(rxJ,ryJ,rzJ,sxJ,syJ,szJ,txJ,tyJ,tzJ),J,
                     tuple(nxJ,nyJ,nzJ),sJ)
end
