! OUTPUT FILES
!  1: Iteration, position, [velocity] if dynamic
!  2: Iteration, [Kinetic energy, Potential energy, Total energy, Temperature] if dynamic else [Potential energy]
!  3: Relative distance among particles after simulation is over
!  4: Old positions and velocities (continue old simulation)
!  7: ?
!  8: Iteration, cumulative distance from pos0
!  9: Radial distance, g(r)
! 10: pos0
! 11: Thermostat type, T0, coupling

module modulo1
  implicit none
  private
  public :: interazione,kr
  integer,parameter::kr=selected_real_kind(12)
  contains

  subroutine interazione(pos,nbody,f,upot,box)
    real(kind=kr), intent(in), dimension(:,:) :: pos
    integer, intent(in) :: nbody
    real(kind=kr), intent(in) :: box
    real(kind=kr), intent(out) :: upot
    real(kind=kr), intent(out), dimension(:,:) :: f
    real(kind=kr), dimension(size(pos,1)) :: posij, deltaij
    real(kind=kr) :: rij
    integer :: i,j

    upot = 0
    f = 0
    do i=1,nbody
      do j=1,nbody
        if( i==j ) cycle
        posij = pos(:,i)-pos(:,j)
        deltaij = mod(posij,box)
        deltaij = deltaij-box*int(2*deltaij/box)
        rij=sqrt(dot_product(deltaij,deltaij))
        upot = upot + 4*(rij**(-12)-rij**(-6)) 
        f(:,i) = f(:,i) + 24*(2.*rij**(-14)-rij**(-8))*deltaij
      end do
    end do
    upot = upot/2
  end subroutine interazione
end module modulo1

module thermostatRoutines
  use modulo1, rk=>kr

  implicit none
  public
  contains

  subroutine velocityScaling(vel, temperature, T0)
    real(kind=rk), intent(inout), dimension(:,:) :: vel
    real(kind=rk), intent(in) :: temperature, T0

    vel = sqrt(T0 / temperature) * vel
  end subroutine velocityScaling

  subroutine berendsenThermostat(vel, temperature, T0, dt, coupling)
    real(kind=rk), intent(inout), dimension(:,:) :: vel
    real(kind=rk), intent(in) :: temperature, T0, dt, coupling

    vel = sqrt(1 + dt / coupling * (T0 / temperature - 1)) * vel
  end subroutine berendsenThermostat

end module thermostatRoutines

program corpi3d
  use modulo1, rk=>kr
  use thermostatRoutines

  implicit none

  integer, parameter :: nh=100, nbody=864, nstep=3000, nsave=3000, gsave=2, gskip=500
  logical, parameter :: dyn=.TRUE., anneal=.FALSE., cont=.FALSE., pbc=.TRUE.
  real(kind=rk), parameter :: box=10, dt=0.004, vmax=0.001
  real(kind=rk), parameter :: pi=4.*atan(1.)

  integer :: it,ios,i,j,ig,thermostat
  real(kind=rk) :: mepot,mekin,massa=1.,alfa=1., rsq, rad, del, part, temperature, T0, thermostatCoupling
  real(kind=rk),dimension(:,:),allocatable :: pos, pos0
  real(kind=rk),dimension(:),allocatable :: velcm, d, vbox
  real(kind=rk),dimension(:,:),allocatable :: ekin,vel,f
  real(kind=rk),dimension(nh) :: g=0.
  real(kind=rk), dimension(3) :: pij, dij
  real(kind=rk) :: gij

  read(11, *) thermostat, T0, thermostatCoupling

  if (dyn) then
    if (anneal) then
      write(unit=*,fmt="(a)",advance="no")"scaling parameter?"
      read*, alfa
    end if

    write(unit=*,fmt="(a I1 a F8.3 a F8.3)")"Thermostat:", thermostat, ", ", T0, ", ", thermostatCoupling
  end if

  allocate(vel(3,nbody))
  allocate(ekin(3,nbody))
  allocate(pos(3,nbody))
  allocate(pos0(3,nbody))
  allocate(f(3,nbody))
  allocate(velcm(3))
  allocate(d(3))
  vbox=spread(box,1,3)
  del=box/(2*nh)

  !print*,"mass of the bodies: "
  !read*,massa

  vel=0.
  if (cont) then
    read(unit=4) pos,vel
  else
    ! read positions until EOF
    do
      read(unit=10,fmt=*,iostat=ios) pos 
      if (ios<=0) exit
    end do

    if (dyn) then
  !    do
  !      read(unit=9,fmt=*,iostat=ios) vel 
  !      if (ios<=0) exit
  !    end do

      ! [0,1]
      call random_number(vel)
      ! [-1,1]
      vel=2*(vel-0.5)

      ! translate the center of mass to the origin
      do i=1,3
        velcm(i) = sum(vel(i,:))/nbody
        vel(i,:) = vel(i,:) - velcm(i)
      end do

      if (T0.gt.0) then
        temperature = sum(vel**2) / (3._8*(nbody - 1))
        vel = sqrt(T0/temperature) * vel
      end if
      write(unit=1,fmt=*)0,0,pos,vel
    end if
  end if

  pos0=pos
  rsq=sum((pos-pos0)**2) / nbody
  write(unit=8,fmt=*) 0, rsq

  ! compute g
  do i=1,nbody-1
    do j=i+1,nbody
      pij = pos(:,i)-pos(:,j)
      dij = mod(pij,box)
      dij = dij-box*int(2*dij/box)
      gij=sqrt(dot_product(dij,dij))
      if (gij.lt.box/2.) then
        ig=int(gij/del)
        g(ig)=g(ig)+2
      end if
    end do
  end do

  ! write rad/g(rad)
  do i=0,nh-1
    rad=del*(i+.5)
    part=4*pi*rad**2*del*nbody/box**3
    write(unit=9,fmt=*) rad, g(i+1)/(part*nbody)
    g(i+1) = 0
  end do

  call interazione(pos,nbody,f,mepot,box)

  do it = 1,nstep
    write(unit=7,fmt=*) nbody
    write(unit=7,fmt=*)

    if (dyn) then
      ! update positions and velocity
      do i = 1,nbody
        pos(:,i) = pos(:,i) + vel(:,i) * dt + 0.5 * f(:,i)/massa * dt**2
        vel(:,i) = vel(:,i) + 0.5 * dt * f(:,i)/massa
      end do

      if (pbc) then
        pos = mod(pos + box, box)
      end if

      call interazione(pos,nbody,f,mepot,box)
      
      ! compute new velocity and kinetic energy
      do i=1,nbody
        vel(:,i) = vel(:,i) + 0.5 * dt * f(:,i)/massa
        ekin(:,i) = 0.5 * massa * (vel(:,i))**2
      end do

      ! total kinetic energy
      mekin = sum(ekin)

      temperature = mekin * 2 / (3._8*(nbody - 1))

      ! apply thermostat
      select case (thermostat)
      case (0)
        ! do nothing
      case (1)
        call velocityScaling(vel, temperature, T0)
      case (2)
        call berendsenThermostat(vel, temperature, T0, dt, thermostatCoupling)
      case default
        stop "Illegal argument"
      end select

      ! recompute after thermostat
      do i=1,nbody
        ekin(:,i) = 0.5 * massa * (vel(:,i))**2
      end do
      mekin = sum(ekin)
      temperature = mekin * 2 / (3._8*(nbody - 1))

      ! write output
      if (mod(it,nstep/nsave).eq.0) then
        write(unit=1,fmt=*)it,it*dt,pos,vel
        write(unit=2,fmt=*)it,mekin,mepot,mekin+mepot,temperature
      end if

      if (anneal) vel=alfa*vel

      rsq=sum((pos-pos0)**2) / nbody
      write(unit=8,fmt=*) it, rsq
    else ! dyn false
      ! update positions
      do i = 1,nbody
        pos(:,i) = pos(:,i) + f(:,i)/massa * dt**2
      end do

      call interazione(pos,nbody,f,mepot,box)

      ! write positions and potential energy
      if (mod(it,nstep/nsave).eq.0) then
        write(unit=1,fmt=*)it,pos
        write(unit=2,fmt=*)it,mepot
      end if
    end if

    do i = 1,nbody
      d=mod(pos(:,i),box)
      write (unit=7,fmt=*) "Ar", d-box*int(2.*d/box)+vbox/2.
    end do

    if (it.gt.gskip) then
      ! compute g
      do i=1,nbody-1
        do j=i+1,nbody
          pij = pos(:,i)-pos(:,j)
          dij = mod(pij,box)
          dij = dij-box*int(2*dij/box)
          gij=sqrt(dot_product(dij,dij))
          if (gij.lt.box/2.) then
            ig=int(gij/del)
            g(ig)=g(ig)+2
          end if
        end do
      end do

      if (mod(it,nstep/gsave).eq.0) then
        ! write rad/g(rad)
        do i=0,nh-1
          rad=del*(i+.5)
          part=4*pi*rad**2*del*nbody/box**3
          write(unit=9,fmt=*) rad, g(i+1)/(part*nbody) * gsave / nstep
          g(i+1) = 0
        end do
      end if
    end if

  end do ! end of nstep loop
    
  ! write relative distances among particles
  do i=1,nbody
    do j=i+1,nbody
      write(unit=3,fmt=*) i,j,sqrt(dot_product(pos(:,i)-pos(:,j),pos(:,i)-pos(:,j)))
    end do
  end do

  write(unit=4) pos,vel
end program corpi3d