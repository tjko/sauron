/* Raw parse in.named format lines (possibly continued) and print them out */
/* $Id$ */

#include	<stdio.h>
#include	<ctype.h>

main(int argc,char *argv[])	{
  int loop;
  FILE *f;

  for(loop=1; loop<argc; loop++)	{
    unsigned int row=0;
    int parens=0;
    char buffer[BUFSIZ],line[10*BUFSIZ],*p=line,last=0,quote=0;

    if(!(f=fopen(argv[loop],"r")))	{
      fprintf(stderr,"%s: cannot open input file\n",argv[loop]);
      perror(*argv);
      continue;
    }

    while(fgets(buffer,sizeof(buffer),f))	{
      char *q;

      row++;

      for(q=buffer; *q; q++)	{
	if(*q=='"' || *q=='\'')	{
	  if(*q==quote)
	    quote=0;
	  else if(!quote)
	    quote=*q;
	} else if(!quote)	{
	  if(*q=='(')           { 
	    parens++; 
	    *q=' '; 
	  } else if(*q==')')	{
	    *q=' ';
	    if(--parens<0)
	      fprintf(stderr,"%s(%u): misordered parens\n",argv[loop],row);
	  } else if(*q==';')
	    break;
	  else if(isspace(*q))
	    *q=' ';
	}
	if(*q!=' ' || last!=' ')
	  *p++=(last=*q);
      }

      if(quote)	{
	fprintf(stderr,"%s(%u): unterminated %c-quoted string\n",
		argv[loop],row,quote);
	/* I guess this is right, seems in.named does this */
	quote=0;
      }
      
      if(parens<1)	{
	if(last==' ') p--;
	*p='\0';
	puts(line);

	p=line;
	last=0;
	parens=0;
      }
    }
	
    if(parens)
      fprintf(stderr,"%s(%u): unbalanced parens\n",argv[loop],row);

    if(last==' ') p--;
    *p='\0';
    puts(line);

    fclose(f);
  }
  exit(0);
}

   /* * * Otto J. Makela  <otto@cc.jyu.fi> * * * * * * * * * * * * * * * * */
  /* Phone: +358 14 613 847, BBS: +358 14 211 562 (V.32bis/USR-HST,24h/d) */
 /* Mail: Cygn.k.7 E 46/FIN-40100 Jyvaskyla/Finland, ICBM: 62.14N 25.44E */
/* * * Computers Rule 01001111 01001011 * * * * * * * * * * * * * * * * */
