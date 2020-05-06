program ft4sd

! Decode ft4slow data read from *.c2 or *.wav files.

   use packjt77
   include 'ft4s_params.f90'
   parameter (NSPS2=NSPS/32)
   character arg*8,cbits*50,infile*80,fname*16,datetime*11
   character ch1*1,ch4*4,cseq*31
   character*22 decodes(100)
   character*37 msg
   character*120 data_dir
   character*77 c77
   complex c2(0:NMAX/32-1)              !Complex waveform
   complex cframe(0:144*NSPS2-1)               !Complex waveform
   complex cd(0:144*20-1)                   !Complex waveform
   real*8 fMHz
   real llr(240),llra(240),llrb(240),llrc(240),llrd(240)
   real candidates(100,2)
   real bitmetrics(288,4)
   integer ihdr(11)
   integer*2 iwave(NMAX)                 !Generated full-length waveform
   integer*1 apmask(240),cw(240)
   integer*1 hbits(288)
   integer*1 message101(101)
   logical badsync,unpk77_success

   fs=12000.0/NDOWN                       !Sample rate
   dt=1.0/fs                              !Sample interval (s)
   tt=NSPS*dt                             !Duration of "itone" symbols (s)
   txt=NZ*dt                              !Transmission length (s)
   hmod=1.0
   Keff=91

   nargs=iargc()
   if(nargs.lt.1) then
      print*,'Usage:   ft4sd [-a <data_dir>] [-f fMHz] [-h hmod] [-k Keff] file1 [file2 ...]'
      go to 999
   endif
   iarg=1
   data_dir="."
   call getarg(iarg,arg)
   if(arg(1:2).eq.'-a') then
      call getarg(iarg+1,data_dir)
      iarg=iarg+2
      call getarg(iarg,arg)
   endif
   if(arg(1:2).eq.'-f') then
      call getarg(iarg+1,arg)
      read(arg,*) fMHz
      iarg=iarg+2
      call getarg(iarg,arg)
   endif
   if(arg(1:2).eq.'-h') then
      call getarg(iarg+1,arg)
      read(arg,*) hmod 
      iarg=iarg+2
      call getarg(iarg,arg)
   endif
   if(arg(1:2).eq.'-k') then
      call getarg(iarg+1,arg)
      read(arg,*) Keff 
      iarg=iarg+2
   endif

   ngood=0
   do ifile=iarg,nargs
      call getarg(ifile,infile)
      open(10,file=infile,status='old',access='stream')
      j1=index(infile,'.c2')
      j2=index(infile,'.wav')
      if(j1.gt.0) then
         read(10,end=999) fname,ntrmin,fMHz,c2
         read(fname(8:11),*) nutc
         write(datetime,'(i11)') nutc
      else if(j2.gt.0) then
         read(10,end=999) ihdr,iwave
         read(infile(j2-4:j2-1),*) nutc
         datetime=infile(j2-11:j2-1)
         call ft4s_downsample(iwave,c2)
      else
         print*,'Wrong file format?'
         go to 999
      endif
      close(10)

      fa=-100.0
      fb=100.0
      fs=12000.0/32.0
      npts=120*12000.0/32.0

      call getcandidate_ft4s(c2,npts,hmod,fs,fa,fb,ncand,candidates)         !First approx for freq

      del=1.5*hmod*fs/300.0
      ndecodes=0
      do icand=1,ncand
         fc0=candidates(icand,1)
         xsnr=candidates(icand,2)
!write(*,*) 'candidates ',icand,fc0,xsnr
         do isync=0,1

            if(isync.eq.0) then
               fc1=fc0-del
               is0=375
               ishw=350
               isst=30
               ifhw=10
               df=.1
            else if(isync.eq.1) then
               fc1=fc2
               is0=isbest
               ishw=100
               isst=10
               ifhw=10
               df=.02
            endif
            smax=0.0
            do if=-ifhw,ifhw
               fc=fc1+df*if
               do istart=max(1,is0-ishw),is0+ishw,isst
                  call coherent_sync_ft4s(c2,istart,hmod,fc,1,sync)
                  if(sync.gt.smax) then
                     fc2=fc
                     isbest=istart
                     smax=sync
                  endif
               enddo
            enddo
!            write(*,*) ifile,icand,isync,fc1+del,fc2+del,isbest,smax
         enddo

!         if(smax .lt. 100.0 ) cycle
!isbest=375
!fc2=-del
         do ijitter=0,2
            if(ijitter.eq.0) ioffset=0
            if(ijitter.eq.1) ioffset=45
            if(ijitter.eq.2) ioffset=-45
            is0=isbest+ioffset
            if(is0.lt.0) cycle
            cframe=c2(is0:is0+144*300-1)
            call downsample_ft4s(cframe,fc2+del,hmod,cd)
            s2=sum(cd*conjg(cd))/(20*144)
            cd=cd/sqrt(s2)
            call get_ft4s_bitmetrics(cd,hmod,bitmetrics,badsync)

            hbits=0
            where(bitmetrics(:,1).ge.0) hbits=1
            ns1=count(hbits(  1:  8).eq.(/0,0,0,1,1,0,1,1/))
            ns2=count(hbits( 57: 64).eq.(/0,1,0,0,1,1,1,0/))
            ns3=count(hbits(113:120).eq.(/1,1,1,0,0,1,0,0/))
            ns4=count(hbits(169:176).eq.(/1,0,1,1,0,0,0,1/))
            ns5=count(hbits(225:232).eq.(/0,0,1,1,1,0,0,1/))
            ns6=count(hbits(281:288).eq.(/0,1,1,1,0,0,1,0/))
            nsync_qual=ns1+ns2+ns3+ns4+ns5+ns6
!          if(nsync_qual.lt. 20) cycle

            scalefac=2.83
            llra(  1: 48)=bitmetrics(  9: 56, 1)
            llra( 49: 96)=bitmetrics( 65:112, 1)
            llra( 97:144)=bitmetrics(121:168, 1)
            llra(145:192)=bitmetrics(177:224, 1)
            llra(193:240)=bitmetrics(233:280, 1)
            llra=scalefac*llra
            llrb(  1: 48)=bitmetrics(  9: 56, 2)
            llrb( 49: 96)=bitmetrics( 65:112, 2)
            llrb( 97:144)=bitmetrics(121:168, 2)
            llrb(145:192)=bitmetrics(177:224, 2)
            llrb(193:240)=bitmetrics(233:280, 2)
            llrb=scalefac*llrb
            llrc(  1: 48)=bitmetrics(  9: 56, 3)
            llrc( 49: 96)=bitmetrics( 65:112, 3)
            llrc( 97:144)=bitmetrics(121:168, 3)
            llrc(145:192)=bitmetrics(177:224, 3)
            llrc(193:240)=bitmetrics(233:280, 3)
            llrc=scalefac*llrc
            llrd(  1: 48)=bitmetrics(  9: 56, 4)
            llrd( 49: 96)=bitmetrics( 65:112, 4)
            llrd( 97:144)=bitmetrics(121:168, 4)
            llrd(145:192)=bitmetrics(177:224, 4)
            llrd(193:240)=bitmetrics(233:280, 4)
            llrd=scalefac*llrd
            apmask=0
            max_iterations=40

            do itry=4,1,-1
               if(itry.eq.1) llr=llra
               if(itry.eq.2) llr=llrb
               if(itry.eq.3) llr=llrc
               if(itry.eq.4) llr=llrd
               nhardbp=0
               nhardosd=0
               dmin=0.0
               call bpdecode240_101(llr,apmask,max_iterations,message101,cw,nhardbp,niterations,nchecks)
!               if(nhardbp.lt.0) call osd240_101(llr,Keff,apmask,5,message101,cw,nhardosd,dmin)
               maxsuperits=2
               ndeep=3  ! use ndeep=3 with Keff=91
               if(Keff.eq.77) ndeep=4
               if(nhardbp.lt.0) then
!                  call osd240_101(llr,Keff,apmask,ndeep,message101,cw,nhardosd,dmin)
                  call decode240_101(llr,Keff,ndeep,apmask,maxsuperits,message101,cw,nhardosd,iter,ncheck,dmin,isuper)
               endif
               if(nhardbp.ge.0 .or. nhardosd.ge.0) then
                  write(c77,'(77i1)') message101(1:77)
                  call unpack77(c77,0,msg,unpk77_success)
                  if(unpk77_success .and. index(msg,'K9AN').gt.0) then
                     ngood=ngood+1
                     write(*,1100) ifile-2,icand,xsnr,isbest/375.0-1.0,1500.0+fc2+del,msg(1:20),itry,nhardbp,nhardosd,dmin,ijitter
1100                 format(i5,2x,i5,2x,f6.1,2x,f6.2,2x,f8.2,2x,a20,i4,i4,i4,f7.2,i6)
                     goto 2002 
                  else
                     cycle
                  endif
               endif
            enddo  ! metrics
         enddo  ! istart jitter
      enddo !candidate list
2002  continue
   enddo !files
   nfiles=nargs-iarg+1
   write(*,*) 'nfiles: ',nfiles,' ngood: ',ngood
   write(*,1120)
1120 format("<DecodeFinished>")

999 end program ft4sd

subroutine coherent_sync_ft4s(cd0,i0,hmod,f0,itwk,sync)

! Compute sync power for a complex, downsampled FT4s signal.

   include 'ft4s_params.f90'
   parameter(NP=NMAX/NDOWN,NSS=NSPS/NDOWN)
   complex cd0(0:NP-1)
   complex csynca(4*NSS),csyncb(4*NSS)
   complex csyncc(4*NSS),csyncd(4*NSS)
   complex csynce(4*NSS),csyncf(4*NSS)
   complex csync2(4*NSS)
   complex ctwk(4*NSS)
   complex z1,z2,z3,z4,z5,z6
   logical first
   integer icos4a(0:3),icos4b(0:3)
   integer icos4c(0:3),icos4d(0:3)
   integer icos4e(0:3),icos4f(0:3)
   data icos4a/0,1,3,2/
   data icos4b/1,0,2,3/
   data icos4c/2,3,1,0/
   data icos4d/3,2,0,1/
   data icos4e/0,2,3,1/
   data icos4f/1,2,0,3/
   data first/.true./
   save first,twopi,csynca,csyncb,csyncc,csyncd,csynce,csyncf,fac

   p(z1)=(real(z1*fac)**2 + aimag(z1*fac)**2)**0.5          !Statement function for power

   if( first ) then
      twopi=8.0*atan(1.0)
      k=1
      phia=0.0
      phib=0.0
      phic=0.0
      phid=0.0
      phie=0.0
      phif=0.0
      do i=0,3
         dphia=twopi*hmod*icos4a(i)/real(NSS)
         dphib=twopi*hmod*icos4b(i)/real(NSS)
         dphic=twopi*hmod*icos4c(i)/real(NSS)
         dphid=twopi*hmod*icos4d(i)/real(NSS)
         dphie=twopi*hmod*icos4e(i)/real(NSS)
         dphif=twopi*hmod*icos4f(i)/real(NSS)
         do j=1,NSS
            csynca(k)=cmplx(cos(phia),sin(phia))
            csyncb(k)=cmplx(cos(phib),sin(phib))
            csyncc(k)=cmplx(cos(phic),sin(phic))
            csyncd(k)=cmplx(cos(phid),sin(phid))
            csynce(k)=cmplx(cos(phie),sin(phie))
            csyncf(k)=cmplx(cos(phif),sin(phif))
            phia=mod(phia+dphia,twopi)
            phib=mod(phib+dphib,twopi)
            phic=mod(phic+dphic,twopi)
            phid=mod(phid+dphid,twopi)
            phie=mod(phie+dphie,twopi)
            phif=mod(phif+dphif,twopi)
            k=k+1
         enddo
      enddo
      first=.false.
      fac=1.0/(4.0*NSS)
   endif

   i1=i0                            !four Costas arrays
   i2=i0+28*NSS
   i3=i0+56*NSS
   i4=i0+84*NSS
   i5=i0+112*NSS
   i6=i0+140*NSS

   z1=0.
   z2=0.
   z3=0.
   z4=0.
   z5=0.
   z6=0.

   if(itwk.eq.1) then
      dt=1/(12000.0/32.0)
      dphi=twopi*f0*dt
      phi=0.0
      do i=1,4*NSS
         ctwk(i)=cmplx(cos(phi),sin(phi))
         phi=mod(phi+dphi,twopi)
      enddo
   endif

   if(itwk.eq.1) csync2=ctwk*csynca      !Tweak the frequency
   if(i1.ge.0 .and. i1+4*NSS-1.le.NP-1) then
      z1=sum(cd0(i1:i1+4*NSS-1)*conjg(csync2))
   elseif( i1.lt.0 ) then
      npts=(i1+4*NSS-1)/2
      if(npts.le.40) then
         z1=0.
      else
         z1=sum(cd0(0:i1+4*NSS-1)*conjg(csync2(4*NSS-npts:)))
      endif
   endif

   if(itwk.eq.1) csync2=ctwk*csyncb      !Tweak the frequency
   if(i2.ge.0 .and. i2+4*NSS-1.le.NP-1) then
      z2=sum(cd0(i2:i2+4*NSS-1)*conjg(csync2))
   endif

   if(itwk.eq.1) csync2=ctwk*csyncc      !Tweak the frequency
   if(i3.ge.0 .and. i3+4*NSS-1.le.NP-1) then
      z3=sum(cd0(i3:i3+4*NSS-1)*conjg(csync2))
   endif

   if(itwk.eq.1) csync2=ctwk*csyncd      !Tweak the frequency
   if(i4.ge.0 .and. i4+4*NSS-1.le.NP-1) then
      z4=sum(cd0(i4:i4+4*NSS-1)*conjg(csync2))
   endif

   if(itwk.eq.1) csync2=ctwk*csynce      !Tweak the frequency
   if(i5.ge.0 .and. i5+4*NSS-1.le.NP-1) then
      z5=sum(cd0(i5:i5+4*NSS-1)*conjg(csync2))
   endif

   if(itwk.eq.1) csync2=ctwk*csyncf      !Tweak the frequency
   if(i6.ge.0 .and. i6+4*NSS-1.le.NP-1) then
      z6=sum(cd0(i6:i6+4*NSS-1)*conjg(csync2))
   elseif( i6+4*NSS-1.gt.NP-1 ) then
      npts=(NP-1-i6+1)
      if(npts.le.40) then
         z6=0.
      else
         z6=sum(cd0(i6:i6+npts-1)*conjg(csync2(1:npts)))
      endif
   endif

   sync = p(z1) + p(z2) + p(z3) + p(z4) + p(z5) + p(z6)

   return
end subroutine coherent_sync_ft4s

subroutine downsample_ft4s(ci,f0,hmod,co)
   parameter(NI=144*300,NH=NI/2,NO=NI/15)  ! downsample from 315 samples per symbol to 20 
   complex ci(0:NI-1),ct(0:NI-1)
   complex co(0:NO-1)
   fs=12000.0/32.0
   df=fs/NI
   ct=ci
   call four2a(ct,NI,1,-1,1)             !c2c FFT to freq domain
   i0=nint(f0/df)
   ct=cshift(ct,i0)
   co=0.0
   co(0)=ct(0)
   b=16.0*hmod
   do i=1,NO/2
      arg=(i*df/b)**2
      filt=exp(-arg)
      co(i)=ct(i)*filt
      co(NO-i)=ct(NI-i)*filt
   enddo
   co=co/NO
   call four2a(co,NO,1,1,1)            !c2c FFT back to time domain
   return
end subroutine downsample_ft4s

subroutine getcandidate_ft4s(c,npts,hmod,fs,fa,fb,ncand,candidates)
   parameter(NFFT1=120*12000/32,NH1=NFFT1/2,NFFT2=120*12000/320,NH2=NFFT2/2)
   complex c(0:npts-1)                   !Complex waveform
   complex cc(0:NFFT1-1)
   complex csfil(0:NFFT2-1)
   complex cwork(0:NFFT2-1)
   real bigspec(0:NFFT2-1)
   complex c2(0:NFFT1-1)                 !Short spectra
   real s(-NH1+1:NH1)                    !Coarse spectrum
   real ss(-NH1+1:NH1)                   !Smoothed coarse spectrum
   real candidates(100,2)
   integer indx(NFFT2-1)
   logical first
   data first/.true./
   save first,w,df,csfil

   if(first) then
      df=10*fs/NFFT1
      csfil=cmplx(0.0,0.0)
      do i=0,NFFT2-1
!         csfil(i)=exp(-((i-NH2)/32.0)**2)  ! revisit this
         csfil(i)=exp(-((i-NH2)/(hmod*28.0))**2)  ! revisit this
      enddo
      csfil=cshift(csfil,NH2)
      call four2a(csfil,NFFT2,1,-1,1)
      first=.false.
   endif

   cc=cmplx(0.0,0.0)
   cc(0:npts-1)=c;
   call four2a(cc,NFFT1,1,-1,1)
   cc=abs(cc)**2
   call four2a(cc,NFFT1,1,-1,1)
   cwork(0:NH2)=cc(0:NH2)*conjg(csfil(0:NH2))
   cwork(NH2+1:NFFT2-1)=cc(NFFT1-NH2+1:NFFT1-1)*conjg(csfil(NH2+1:NFFT2-1))

   call four2a(cwork,NFFT2,1,+1,1)
   bigspec=cshift(real(cwork),-NH2)
   il=NH2+fa/df
   ih=NH2+fb/df
   nnl=ih-il+1
   call indexx(bigspec(il:il+nnl-1),nnl,indx)
   xn=bigspec(il-1+indx(nint(0.3*nnl)))
   bigspec=bigspec/xn
   ncand=0
   do i=il,ih
      if((bigspec(i).gt.bigspec(i-1)).and. &
         (bigspec(i).gt.bigspec(i+1)).and. &
         (bigspec(i).gt.1.15).and.ncand.lt.100) then
         ncand=ncand+1
         candidates(ncand,1)=df*(i-NH2)
         candidates(ncand,2)=10*log10(bigspec(i)-1)-26.5
      endif
   enddo
   return
end subroutine getcandidate_ft4s

subroutine ft4s_downsample(iwave,c)

! Input: i*2 data in iwave() at sample rate 12000 Hz
! Output: Complex data in c(), sampled at 375 Hz

   include 'ft4s_params.f90'
   parameter (NFFT2=NMAX/32)
   integer*2 iwave(NMAX)
   complex c(0:NMAX/32-1)
   complex c1(0:NFFT2-1)
   complex cx(0:NMAX/2)
   real x(NMAX)
   equivalence (x,cx)

   df=12000.0/NMAX
   x=iwave
   call four2a(x,NMAX,1,-1,0)             !r2c FFT to freq domain
   i0=nint(1500.0/df)
   c1(0)=cx(i0)
   do i=1,NFFT2/2
      c1(i)=cx(i0+i)
      c1(NFFT2-i)=cx(i0-i)
   enddo
   c1=c1/NFFT2
   call four2a(c1,NFFT2,1,1,1)            !c2c FFT back to time domain
   c=c1(0:NMAX/32-1)
   return
end subroutine ft4s_downsample
