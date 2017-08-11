USE [apeam]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND name = 'MOV_EnviosEUA')
DROP PROCEDURE MOV_EnviosEUA
GO

CREATE PROCEDURE [dbo].[MOV_EnviosEUA]
	@Idsesion int,
	@Opcion int,
	@IdEstado int
	
AS
BEGIN
	

	DECLARE @IdTemporadaActual int
	DECLARE @IdTemporadaAnterior int
	DECLARE @SemanaCorriente int	
	

	SET NOCOUNT ON;

	-- --------------------------------------------
	-- OBTENER ID DE SESION VALIDA
	SET @Idsesion  = (SELECT IdSesion FROM cosechas.dbo.USU_SesionesMoviles 
         where  IdSesion = @Idsesion AND Activo = 1)
    -- --------------------------------------------
	-- SI EL ID DE SESION VALIDA 

	--SI LA SESIÓN ES VÁLIDA
    IF @Idsesion IS NOT NULL
	BEGIN


			SET @IdTemporadaActual = dbo.Temporada(GETDATE())
			SET @IdTemporadaAnterior = @IdTemporadaActual - 1
						
			
			IF @Opcion = 1
			BEGIN
				
				DECLARE @Fecha_inicio_actual date
				DECLARE @Fecha_fin_actual date
				DECLARE @Fecha_inicio_anterior date
				DECLARE @Fecha_fin_anterior date
				DECLARE @añosem varchar(4)
				DECLARE @CurrentWeeksem varchar(2)
					
				--CREACIÓN DE TABLAS
				CREATE TABLE #TempEnviosAnterior
				(
					SemanaTemp int,
					Semana int,
					Toneladas decimal(14,02)					
				)

				CREATE TABLE #TempEnviosActual
				(
					SemanaTemp int,
					Semana int,
					Toneladas decimal(14,02)
				)

				CREATE TABLE #TempComparativoTemporadasSemanal
				(
					SemanaTemporada int,
					Semana int,
					TempAnterior decimal(14,02),
					TempActual decimal(14,02),
					Variacion AS ((TempActual / TempAnterior) -1) * 100
				)
				--Obtengo id temporada actual y anterior
				SET @IdTemporadaActual = (Select IdTemporada from DIV_Temporadas where GETDATE() between Inicio and Fin)
				SET @IdTemporadaAnterior = @IdTemporadaActual - 1
	
				--Obtengo Fecha de inicio y fin de temporada actual
				SET @Fecha_inicio_actual = (Select Inicio from DIV_Temporadas where IdTemporada = @IdTemporadaActual)
				SET @Fecha_fin_actual = (Select Fin from DIV_Temporadas where IdTemporada = @IdTemporadaActual)

				--Obtengo Fecha de inicio y fin temporada anterior
				SET @Fecha_inicio_anterior = (Select Inicio   from DIV_Temporadas where IdTemporada = @IdTemporadaAnterior)
				SET @CurrentWeeksem = dbo.Semana(GETDATE())
				IF @CurrentWeeksem between 27 and 53 
				BEGIN
					SET @añosem = CAST(YEAR((SELECT Inicio FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaAnterior)) AS VARCHAR(4))
				END
				ELSE IF @CurrentWeeksem between 1 and 26 
				BEGIN 
					SET @añosem = CAST(YEAR((SELECT Fin FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaAnterior)) AS VARCHAR(4))
				END
			    SET @Fecha_fin_anterior =	(SELECT Fin FROM DIV_Semanas WHERE Periodo LIKE '%' + @añosem + '%' AND Semana LIKE '%' + @CurrentWeeksem + '%')
				
				
				--OBTENGO ENVIOS POR SEMANA DE TEMPORA "ACTUAL"====================================================
				INSERT INTO #TempEnviosActual(SemanaTemp, Semana, Toneladas)
							SELECT dbo.SemanaTemporada(FechaExpedicion) as SemanaTemp, dbo.Semana(FechaExpedicion) as Semana, 
								SUM(PesoTotal/1000) AS Toneladas
								--SUM(dbo.SOC_Contenedores(PesoTotal,TrailerSelloContenedor)) as Contenedores
							FROM CER_Movimientos
							WHERE FechaExpedicion between @Fecha_inicio_actual and @Fecha_fin_actual
							GROUP BY dbo.SemanaTemporada(FechaExpedicion), dbo.Semana(FechaExpedicion)
							ORDER BY dbo.SemanaTemporada(FechaExpedicion)
			
				
				--OBTENGO ENVIOS POR SEMANA DE TEMPORA "ANTERIOR"====================================================
					INSERT INTO #TempEnviosAnterior(SemanaTemp, Semana, Toneladas)
							SELECT dbo.SemanaTemporada(FechaExpedicion) as SemanaTemp, dbo.Semana(FechaExpedicion) as Semana, 
								SUM(PesoTotal/1000) AS Toneladas
								--SUM(dbo.SOC_Contenedores(PesoTotal,TrailerSelloContenedor)) as Contenedores
							FROM CER_Movimientos
							WHERE FechaExpedicion between @Fecha_inicio_anterior and @Fecha_fin_anterior
							GROUP BY dbo.SemanaTemporada(FechaExpedicion), dbo.Semana(FechaExpedicion)
							ORDER BY dbo.SemanaTemporada(FechaExpedicion)


				--==============================================================================================
				--YA QUE TENGO LA TEMPORADA ACTUAL Y TEMPORADA ANTERIOR EN TABLAS TEMPORALES====================	
				--CUENTO SI TIENEN LOS MISMOS REGISTROS PARA CREAR UNA TERCER TABLA, SINO INSERTO EN============
				--NUEVA TABLA LA TEMPORADA QUE TENGA MAS REGISTROS Y EN SEGUIDA LA OTRA BRINCANDO LA SEM 53=0===
				DECLARE @actualCount int
				DECLARE @anteriorCount int

				SET @actualCount = (SELECT COUNT(*) AS TemporadaActual FROM #TempEnviosActual)
				SET @anteriorCount = (SELECT COUNT(*) AS TemporadaAnterior FROM #TempEnviosAnterior)

				--SI TIENEN IGUAL NÚMERO DE SEMANAS (NO SON BISIESTOS) Ó
				--LA TEMPORADA ANTERIOR TIENEN MÁS SEMANAS (ES BISIESTO)
				IF @anteriorCount = @actualCount OR @anteriorCount > @actualCount
				BEGIN

					--CARGO LAS TONELADAS DE TEMPORADA ANTERIOR
					INSERT INTO #TempComparativoTemporadasSemanal (SemanaTemporada, Semana, TempAnterior) 
					SELECT SemanaTemp, Semana, Toneladas FROM #TempEnviosAnterior
				
					--INSERTO TONELADAS DE TEMPORADA ACTUAL
					DECLARE @SemanaActual int
					DECLARE @ToneladasActual decimal(14,02)

					DECLARE TemporadaActual CURSOR FOR
						SELECT Semana, Toneladas FROM #TempEnviosActual 

					OPEN TemporadaActual

					FETCH NEXT FROM TemporadaActual INTO @SemanaActual, @ToneladasActual

					WHILE @@FETCH_STATUS = 0
					BEGIN
					
						UPDATE #TempComparativoTemporadasSemanal SET TempActual = @ToneladasActual
						WHERE Semana = @SemanaActual

						FETCH NEXT FROM TemporadaActual INTO @SemanaActual, @ToneladasActual
					END

					CLOSE TemporadaActual
					DEALLOCATE TemporadaActual

					--REGRESO TABLA CON TEMPORADAS Y POR SEPARADO, QUÉ TEMPORADAS ESTÁN IMPLICADAS
					SELECT Semana, TempAnterior, TempActual, Variacion FROM #TempComparativoTemporadasSemanal
					SELECT SUBSTRING(Temporada,11,9) AS TemporadaAnterior FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaAnterior
					SELECT SUBSTRING(Temporada,11,9) AS TemporadaActual FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaActual

				END


				--SI TEMPORADA ACTUAL TIENE MÁS SEMANAS (ES BISIESTO)
				--PRIMERO INSERTO TEMP ACTUAL Y DESPUÉS ANTERIOR 
				IF @actualCount > @anteriorCount
				BEGIN
					--CARGO LAS TONELADAS DE TEMPORADA ACTUAL PRIMERO (BISIESTO FIRST)
					INSERT INTO #TempComparativoTemporadasSemanal (SemanaTemporada, Semana, TempActual) 
					SELECT SemanaTemp, Semana, Toneladas FROM #TempEnviosActual
				
					--INSERTO TONELADAS DE TEMPORADA ANTERIOR
					DECLARE @SemanaAnterior int
					DECLARE @ToneladasAnterior decimal(14,02)

					DECLARE TemporadaAnterior CURSOR FOR
						SELECT Semana, Toneladas FROM #TempEnviosAnterior 

					OPEN TemporadaAnterior

					FETCH NEXT FROM TemporadaAnterior INTO @SemanaAnterior, @ToneladasAnterior

					WHILE @@FETCH_STATUS = 0
					BEGIN
						UPDATE #TempComparativoTemporadasSemanal SET TempAnterior = @ToneladasAnterior
						WHERE Semana = @SemanaAnterior

						FETCH NEXT FROM TemporadaAnterior INTO @SemanaAnterior, @ToneladasAnterior
					END

					CLOSE TemporadaAnterior
					DEALLOCATE TemporadaAnterior

					--REGRESO TABLA CON TEMPORADAS Y POR SEPARADO, QUÉ TEMPORADAS ESTÁN IMPLICADAS
					SELECT Semana, TempAnterior, TempActual, Variacion FROM #TempComparativoTemporadasSemanal
					SELECT SUBSTRING(Temporada,11,9) AS TemporadaAnterior FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaAnterior
					SELECT SUBSTRING(Temporada,11,9) AS TemporadaActual FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaActual
						
				END
				
				DROP TABLE #TempEnviosAnterior
				DROP TABLE #TempEnviosActual
				DROP TABLE #TempComparativoTemporadasSemanal

			END

		



			--OBTIENE EL COMPARATIVO DE MOVILIZACIÓN A EUA POR CALIBRES (TEMP ANTERIOR VS ACTUAL)
			IF @Opcion = 2
			BEGIN 


	
				DECLARE @añoCal varchar(4)
				DECLARE @CurrentWeekCal varchar(2)


				CREATE TABLE #comparativo_final
				(
					Calibre varchar(5),
					TempAnterior decimal(14,02),
					TempActual decimal(14,02),
					Variacion as ((TempActual/TempAnterior) - 1) * 100
				)	

				Insert into #comparativo_final(Calibre) values ('32')
				Insert into #comparativo_final(Calibre) values ('36')
				Insert into #comparativo_final(Calibre) values ('40')
				Insert into #comparativo_final(Calibre) values ('48')
				Insert into #comparativo_final(Calibre) values ('60')
				Insert into #comparativo_final(Calibre) values ('70')
				Insert into #comparativo_final(Calibre) values ('84')
				Insert into #comparativo_final(Calibre,TempActual,TempAnterior) values ('OTROS',0,0)
				
				--Obtengo id temporada actual y anterior
				SET @IdTemporadaActual = (Select IdTemporada from DIV_Temporadas where GETDATE() between Inicio and Fin)
				SET @IdTemporadaAnterior = @IdTemporadaActual - 1
	
				--Obtengo Fecha de inicio y fin de temporada actual
				SET @Fecha_inicio_actual = (Select Inicio from DIV_Temporadas where IdTemporada = @IdTemporadaActual)
				SET @Fecha_fin_actual = (Select Fin from DIV_Temporadas where IdTemporada = @IdTemporadaActual)

				--Obtengo Fecha de inicio y fin temporada anterior
				SET @Fecha_inicio_anterior = (Select Inicio   from DIV_Temporadas where IdTemporada = @IdTemporadaAnterior)
				SET @CurrentWeekCal = dbo.Semana(GETDATE())
				IF @CurrentWeekCal between 27 and 53 
				BEGIN
					SET @añoCal = CAST(YEAR((SELECT Inicio FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaAnterior)) AS VARCHAR(4))
				END
				ELSE IF @CurrentWeekCal between 1 and 26 
				BEGIN 
					SET @añoCal = CAST(YEAR((SELECT Fin FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaAnterior)) AS VARCHAR(4))
				END
				
				PRINT @CurrentWeekCal
			    SET @Fecha_fin_anterior =	(SELECT Fin FROM DIV_Semanas WHERE Periodo LIKE '%' + @añoCal + '%' AND Semana LIKE '%' + @CurrentWeekCal + '%')

				
				--Toneladas por Calibres temporada actual
					
					DECLARE @Calibres varchar(6)
					DECLARE @ToneladasCal decimal(14,02)

					DECLARE Cosecha_Actual CURSOR FOR
						Select calibres.Calibre,sum(detalle.PesoKilogramos)/1000 as toneladas from CER_Movimientos certificados
						inner join CER_DetalleProductos detalle on certificados.IdCertificado = detalle.IdCertificado   
						inner join PRO_Calibres calibres on detalle.IdCalibre = calibres.IdCalibre
						where FechaExpedicion between @Fecha_inicio_actual and @Fecha_fin_actual group by calibres.Calibre order by calibres.Calibre asc
					OPEN Cosecha_Actual

					FETCH NEXT FROM Cosecha_Actual INTO @Calibres, @ToneladasCal

					WHILE @@FETCH_STATUS = 0
					BEGIN							
						Update  #comparativo_final set TempActual = @ToneladasCal where Calibre = @Calibres	
						Update  #comparativo_final set TempActual = TempActual+@ToneladasCal where Calibre = 'OTROS' and '32' != @Calibres   and '36' != @Calibres
						 and '40' != @Calibres and '48' != @Calibres and '60' != @Calibres and '70' != @Calibres and '84' != @Calibres
						FETCH NEXT FROM Cosecha_Actual INTO @Calibres, @ToneladasCal
			
					END

					CLOSE Cosecha_Actual
					DEALLOCATE Cosecha_Actual
					
				--Toneladas por Calibres temporada anterior		
			
					DECLARE Cosecha_Anterior CURSOR FOR
						Select calibres.Calibre,sum(detalle.PesoKilogramos)/1000 from CER_Movimientos certificados
						inner join CER_DetalleProductos detalle on certificados.IdCertificado = detalle.IdCertificado   
						inner join PRO_Calibres calibres on detalle.IdCalibre = calibres.IdCalibre
					where FechaExpedicion between @Fecha_inicio_anterior and @Fecha_fin_anterior group by calibres.Calibre order by calibres.Calibre asc
					OPEN Cosecha_Anterior

					FETCH NEXT FROM Cosecha_Anterior INTO @Calibres, @ToneladasCal

					WHILE @@FETCH_STATUS = 0
					BEGIN
						Update  #comparativo_final set TempAnterior = @ToneladasCal where Calibre = @Calibres	
						Update  #comparativo_final set TempAnterior = TempAnterior+@ToneladasCal where Calibre = 'OTROS' and '32' != @Calibres   and '36' != @Calibres
						 and '40' != @Calibres and '48' != @Calibres and '60' != @Calibres and '70' != @Calibres and '84' != @Calibres
						FETCH NEXT FROM Cosecha_Anterior INTO @Calibres, @ToneladasCal
					END
			
					CLOSE Cosecha_Anterior
					DEALLOCATE Cosecha_Anterior
				
					SELECT * from #comparativo_final
					SELECT SUBSTRING(Temporada,11,9) AS TemporadaAnterior FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaAnterior
					SELECT SUBSTRING(Temporada,11,9) AS TemporadaActual FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaActual

					DROP TABLE #comparativo_final


			END





			--OBTIENE EL COMPARATIVO DE MOVILIZACIÓN A EUA POR ESTADOS (TEMP ANTERIOR VS ACTUAL)
			IF @Opcion = 3
			BEGIN
				
				CREATE TABLE #ResMovilizacionEstados
				(
					IdEstado int,
					Estado varchar(50),
					Contenedores int,
					Kilogramos decimal(14,02),
					Toneladas decimal(14,02),
					Cajas int
				)

				
				CREATE TABLE #TempComparativoEstado
				(
					IdEstado int,
					Estado varchar(50),
					TempAnterior decimal(14,02),
					TempActual decimal(14,02),
					Variacion AS ((TempActual / TempAnterior) -1) * 100
				)


				--OBTENGO LA FECHA DE INICIO Y FIN DE TEMPORADA ANTERIOR A LA SEMANA ACTUAL=============================================
				DECLARE @FechaInicioAnterior date
				DECLARE @FechaFinAnterior date
				DECLARE @año varchar(4)
				DECLARE @CurrentWeek varchar(2)

				SET @FechaInicioAnterior = (SELECT Inicio FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaAnterior)
				
				SET @CurrentWeek = dbo.Semana(GETDATE())
				
				IF @CurrentWeek between 27 and 53 
				BEGIN
					SET @año = CAST(YEAR((SELECT Inicio FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaAnterior)) AS VARCHAR(4))
				END
				ELSE IF @CurrentWeek between 1 and 26 
				BEGIN 
					SET @año = CAST(YEAR((SELECT Fin FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaAnterior)) AS VARCHAR(4))
				END
			
			    SET @FechaFinAnterior =	(SELECT Fin FROM DIV_Semanas WHERE Periodo LIKE '%' + @año + '%' AND Semana LIKE '%' + @CurrentWeek + '%')


				--OBTENGO LA FECHA DE INICIO Y FIN DE TEMPORADA ACTUAL A LA SEMANA CORRIENTE DE TEMPORADA==============================
				DECLARE @FechaInicioActual date
				DECLARE @FechaFinActual date
				
				SET @FechaInicioActual = (SELECT Inicio FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaActual)

				SET @FechaFinActual = (SELECT Fin FROM DIV_Semanas WHERE GETDATE() BETWEEN Inicio and Fin)

				

				--OBTENGO LA MOVILIZACIÓN DE TEMPORADA ACTUAL=========================================================================
				INSERT INTO #ResMovilizacionEstados (IdEstado, Estado, Contenedores, Kilogramos, Toneladas, Cajas)
				EXEC SOC_EstadUSA 13,0,0,0,0,0,@FechaInicioActual,@FechaFinActual

				INSERT INTO #TempComparativoEstado(IdEstado, Estado, TempActual)
				SELECT IdEstado, Estado, Toneladas FROM #ResMovilizacionEstados

				--BORRO TABLA TEMPORAL ANTES DE USARLA DE NUEVO
				DELETE FROM #ResMovilizacionEstados
				
				

				--OBTENGO LA MOVILIZACIÓN DE TEMPORADA ANTERIOR TEMPORALMENTE=========================================================
				INSERT INTO #ResMovilizacionEstados (IdEstado, Estado, Contenedores, Kilogramos, Toneladas, Cajas)
				EXEC SOC_EstadUSA 13,0,0,0,0,0,@FechaInicioAnterior ,@FechaFinAnterior

				--OBTENGO LA MOVILIZACIÓN DE TEMPORADA ANTERIOR Y LA AGREGO A TABLA FINAL
				--DECLARE @IdEstado int
				DECLARE @Estado varchar(50)
				DECLARE @Tons decimal(14,02)

				DECLARE MovilizacionEstados CURSOR FOR
					SELECT IdEstado, Estado, Toneladas FROM #ResMovilizacionEstados


				OPEN MovilizacionEstados

				FETCH NEXT FROM MovilizacionEstados INTO @IdEstado, @Estado, @Tons

				WHILE @@FETCH_STATUS = 0
				BEGIN
					
					IF @IdEstado = (SELECT IdEstado FROM #TempComparativoEstado WHERE IdEstado = @IdEstado)
					BEGIN
						UPDATE #TempComparativoEstado SET TempAnterior = @Tons WHERE IdEstado = @IdEstado
						FETCH NEXT FROM MovilizacionEstados INTO @IdEstado, @Estado, @Tons
					END
					ELSE
					BEGIN
						INSERT INTO #TempComparativoEstado(IdEstado, Estado, TempAnterior) VALUES (@IdEstado, @Estado, @Tons)
						FETCH NEXT FROM MovilizacionEstados INTO @IdEstado, @Estado, @Tons
					END
					
					
				END

				CLOSE MovilizacionEstados
				DEALLOCATE MovilizacionEstados

				--REGRESO TABLA CON TEMPORADAS Y POR SEPARADO, QUÉ TEMPORADAS ESTÁN IMPLICADAS
				SELECT * FROM #TempComparativoEstado ORDER BY TempActual DESC
				SELECT SUBSTRING(Temporada,11,9) AS TemporadaAnterior FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaAnterior
				SELECT SUBSTRING(Temporada,11,9) AS TemporadaActual FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaActual
							


				DROP TABLE #ResMovilizacionEstados
				DROP TABLE #TempComparativoEstado

			END






			--MOVILIZACIÓN A EUA POR CATEGORÍA SICFI (Acumulado de temporada)
			IF @Opcion = 4
			BEGIN								
				
				CREATE TABLE #TEMPENVIOS 
				(
					ToneladasHoyTemporadaActual	varchar(max),
					ToneladasHoyTemporadaANTERIOR	varchar(max),
					Variacion	varchar(max),
					PorcentajeVariacion	varchar(max),
					FrutaRestanteProyectada	varchar(max),
					ToneladasEnCaminoHoy	varchar(max),
					ContenedoresEnCaminoHoy	varchar(max),
					ContenedoresAcumuladoSemana	varchar(max),
					TonsEnvidasSemanaActual	varchar(max),
					TonsEnvidasSemanaAnterior	varchar(max),
					PorcentajeSemanaActualCategoria1SICFI	decimal(12,02),
					PorcentajeSemanaActualCategoria2SICFI	decimal(12,02),
					PorcentajeSemanaAnteriorCategoria1SICFI	decimal(12,02),
					PorcentajeSemanaAnteriorCategoria2SICFI	decimal(12,02)
				)
				
				DECLARE @ToneladasTemporadaCat1 int
				DECLARE @ToneladasTemporadaCat2 int
				
				DECLARE @ToneladasTotalesSICFI int
				DECLARE @InicioTemporada date
				DECLARE @FechaActual date
				
				DECLARE @PorcentajeAcumuladoCat1 decimal(14,2)
				DECLARE @PorcentajeAcumuladoCat2 decimal(14,2)
				
				DECLARE @ToneladasTemporadaEmbarques int
				DECLARE @PorcentajeSICFI_vs_SICOA decimal(14,2)
			
				SET @InicioTemporada = (SELECT Inicio FROM DIV_Temporadas WHERE IdTemporada = @IdTemporadaActual)
				SET @FechaActual = (GETDATE())
				
				EXEC @ToneladasTemporadaCat1 = cosechas.dbo.FnSumaEmbarquesEnEstosPeriodosSICFI @Inicio = @InicioTemporada, @Fin = @FechaActual, @Categoria = 1, @idEstado = @IdEstado
				EXEC @ToneladasTemporadaCat2 = cosechas.dbo.FnSumaEmbarquesEnEstosPeriodosSICFI @Inicio = @InicioTemporada, @Fin = @FechaActual, @Categoria = 2, @idEstado = @IdEstado
				
				SET @ToneladasTotalesSICFI = (@ToneladasTemporadaCat1 + @ToneladasTemporadaCat2)								
	
				SET @PorcentajeAcumuladoCat1 = 0
				SET @PorcentajeAcumuladoCat2 = 0							
				
				
				IF @ToneladasTemporadaCat1 > 0 AND @ToneladasTemporadaCat2 > 0
				BEGIN
					SET @PorcentajeAcumuladoCat1 = (CAST((@ToneladasTemporadaCat1 * 100) AS Decimal(14,2)) / CAST((@ToneladasTemporadaCat1 + @ToneladasTemporadaCat2) AS Decimal(14,2)))
					SET @PorcentajeAcumuladoCat2 = (CAST((@ToneladasTemporadaCat2 * 100) AS Decimal(14,2)) / CAST((@ToneladasTemporadaCat1 + @ToneladasTemporadaCat2) AS Decimal(14,2)))
				END
																											
				
				INSERT INTO #TEMPENVIOS(
							ToneladasHoyTemporadaActual,
							ToneladasHoyTemporadaANTERIOR	,
							Variacion	,
							PorcentajeVariacion	,
							FrutaRestanteProyectada	,
							ToneladasEnCaminoHoy	,
							ContenedoresEnCaminoHoy	,
							ContenedoresAcumuladoSemana	,
							TonsEnvidasSemanaActual	,
							TonsEnvidasSemanaAnterior	,
							PorcentajeSemanaActualCategoria1SICFI	,
							PorcentajeSemanaActualCategoria2SICFI	,
							PorcentajeSemanaAnteriorCategoria1SICFI	,
							PorcentajeSemanaAnteriorCategoria2SICFI	)
				EXEC cosechas.dbo.DIR_Embarques1 16
				
				SET @ToneladasTemporadaEmbarques =  CAST(REPLACE((SELECT ToneladasHoyTemporadaActual as EnviosEUA from #TEMPENVIOS),',','') AS int)								
				
				SET @PorcentajeSICFI_vs_SICOA = (CAST(@ToneladasTotalesSICFI as decimal(14,2)) / CAST(@ToneladasTemporadaEmbarques as decimal(14,2))) * 100
						
				
				SELECT
					@ToneladasTemporadaCat1 ToneladasCat1,
					@ToneladasTemporadaCat2 ToneladasCat2,
					@PorcentajeAcumuladoCat1 PorcentajeCat1,
					@PorcentajeAcumuladoCat2 PorcentajeCat2,
					@ToneladasTotalesSICFI ToneladasSICFI,
					@PorcentajeSICFI_vs_SICOA PorcentajeSICFI
						
				DROP TABLE #TEMPENVIOS
														
			END





			--MOVILIZACIÓN A EUA POR CATEGORÍA SICFI (Acumulado de la semana corriente)
			IF @Opcion = 5
			BEGIN
				
				DECLARE @ToneladasSemanaCat1 int
				DECLARE @ToneladasSemanaCat2 int
				DECLARE @InicioSemanaCorriente date
				DECLARE @FinSemanaCorriente date
				DECLARE @PorcentajeSemanaActualCat1 decimal(14,2)
				DECLARE @PorcentajeSemanaActualCat2 decimal(14,2)
				
				SET @FechaActual = (GETDATE())
				SET @InicioSemanaCorriente = (SELECT Inicio FROM DIV_Semanas WHERE @FechaActual BETWEEN Inicio AND Fin)
				SET @FinSemanaCorriente = (SELECT Fin FROM DIV_Semanas WHERE @FechaActual BETWEEN Inicio AND Fin)
								
				EXEC @ToneladasSemanaCat1 = cosechas.dbo.FnSumaEmbarquesEnEstosPeriodosSICFI @Inicio = @InicioSemanaCorriente, @Fin = @FinSemanaCorriente, @Categoria = 1, @idEstado = @IdEstado
				EXEC @ToneladasSemanaCat2 = cosechas.dbo.FnSumaEmbarquesEnEstosPeriodosSICFI @Inicio = @InicioSemanaCorriente, @Fin = @FinSemanaCorriente, @Categoria = 2, @idEstado = @IdEstado
												
				SET @PorcentajeSemanaActualCat1 = 0
				SET @PorcentajeSemanaActualCat2 = 0
				
				IF @ToneladasSemanaCat1 > 0 AND @ToneladasSemanaCat2 > 0
				BEGIN
					SET @PorcentajeSemanaActualCat1 = (CAST((@ToneladasSemanaCat1 * 100) AS Decimal(14,02)) / CAST((@ToneladasSemanaCat1 + @ToneladasSemanaCat2) AS Decimal(14,02)))
					SET @PorcentajeSemanaActualCat2 = (CAST((@ToneladasSemanaCat2 * 100) AS Decimal(14,02)) / CAST((@ToneladasSemanaCat1 + @ToneladasSemanaCat2) AS Decimal(14,02)))
				END												
				
				SELECT 
					@ToneladasSemanaCat1 ToneladasCat1,
					@ToneladasSemanaCat2 ToneladasCat2,
					@PorcentajeSemanaActualCat1 PorcentajeCat1,
					@PorcentajeSemanaActualCat2 PorcentajeCat2				
				
			END
		
	END
	
		
		
END

