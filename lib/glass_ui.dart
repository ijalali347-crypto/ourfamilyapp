import 'dart:ui';
import 'package:flutter/material.dart';

class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft,end: Alignment.bottomRight,colors:[Color(0xFFE9F3FF),Color(0xFFF5EEFF),Color(0xFFE9FFF7)]))),
    const Positioned(top:-100,left:-70,child:_Glow(size:260,color:Color(0x665B5FEF))),
    const Positioned(top:150,right:-100,child:_Glow(size:300,color:Color(0x5549C6E5))),
    const Positioned(bottom:-110,left:40,child:_Glow(size:320,color:Color(0x554DD8A6))),
    child,
  ]);
}
class _Glow extends StatelessWidget {
  const _Glow({required this.size,required this.color});
  final double size; final Color color;
  @override Widget build(BuildContext context)=>ImageFiltered(imageFilter:ImageFilter.blur(sigmaX:42,sigmaY:42),child:Container(width:size,height:size,decoration:BoxDecoration(shape:BoxShape.circle,color:color)));
}
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key,required this.child,this.padding=const EdgeInsets.all(18),this.margin,this.radius=24});
  final Widget child; final EdgeInsetsGeometry padding; final EdgeInsetsGeometry? margin; final double radius;
  @override Widget build(BuildContext context){
    final r=BorderRadius.circular(radius);
    return Container(margin:margin,child:ClipRRect(borderRadius:r,child:BackdropFilter(filter:ImageFilter.blur(sigmaX:18,sigmaY:18),child:Container(padding:padding,decoration:BoxDecoration(borderRadius:r,color:Colors.white.withOpacity(.48),border:Border.all(color:Colors.white.withOpacity(.72)),boxShadow:[BoxShadow(color:Colors.black.withOpacity(.06),blurRadius:24,offset:const Offset(0,10))]),child:child))));
  }
}
