#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

$LOAD_PATH.push(File::dirname(__FILE__)) ;

require 'Stat_Gaussian.rb' ;

##======================================================================
class ShiftedSq
  ##@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  attr :amp, true ;
  attr :x0, true ;
  attr :x1, true ;
  attr :k, true ;

  ##--------------------------------------------------
  def initialize(a = -1.0, x0 = -1, x1 = 1, k = 2)
    @amp = a ;
    @x0 = x0 ;
    @x1 = x1 ;
    @k = k ;
  end

  ##--------------------------------------------------
  def calcXY(xx)
    y = @amp * (xx - @x0) * (xx - @x1) ;
    x = xx + @k * y ;
    return [x,y] ;
  end

  ##--------------------------------------------------
  def isUnder?(x,y)
    xx = x - @k * y ;
    (xb,yb) = self.calcXY(xx) ;
    return y < yb ;
  end

end ##class ShiftedSq

##======================================================================
class ShiftedEllipse
  ##@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  attr :x0, true ;
  attr :y0, true ;
  attr :rx, true ;
  attr :ry, true ;
  attr :rol, true ;

  ##--------------------------------------------------
  def initialize(x0,y0,rx,ry,rol)
    @x0 = x0 ;
    @y0 = y0 ;
    @rx = rx ;
    @ry = ry ;
    @rol = rol ;
  end

  ##--------------------------------------------------
  def isInside?(x,y)
    dx = x - @x0 ;
    dy = y - @y0 ;
    u = dx * Math::cos(@rol) + dy * Math::sin(@rol) ;
    v = - dx * Math::sin(@rol) + dy * Math::cos(@rol) ;
    r = ((u / rx) ** 2) + ((v / ry) ** 2)
    return r < 1.0 ;
  end

end ##class ShiftedEllipse

##======================================================================
class AistMark
  ##@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  attr :sq0, true ;
  attr :sq1, true ;
  attr :ell, true ;
  attr :bottom, true ;
  attr :noise, true ;

  ##--------------------------------------------------
  def initialize(noise = nil)
    @sq0 = ShiftedSq.new(-1,-1,1,1) ;
    @sq1 = ShiftedSq.new(-0.9,-0.99,0.7,1) ;
    @ell = ShiftedEllipse.new(0.4,0.3,0.8,0.2,0.2)
    @bottom = 0.0 ;
    @noise = noise ;
  end

  ##--------------------------------------------------
  def isInside?(x,y)
    return ((y > @bottom) &
            (@sq0.isUnder?(x,y) ^
             @sq1.isUnder?(x,y) ^
             @ell.isInside?(x,y))) ;
  end

  ##--------------------------------------------------
  def isInsideNoisy?(x,y)
    if(@noise)
      x += @noise.value ;
      y += @noise.value ;
    end
    return isInside?(x,y) ;
  end

  ##--------------------------------------------------
  def isInsideGraded?(x,y,n=100,onesidep=false)
    if(onesidep) then
      if(isInside?(x,y))
        return 1.0 ;
      else
        return isInsideGraded?(x,y,n,false) ;
      end
    else
      c = 0 ;
      (0...n).each{|i|
        c += 1 if(self.isInsideNoisy?(x,y)) ;
      }
      return (c.to_f / n.to_f) ;
    end
  end

end ##class AistMark


