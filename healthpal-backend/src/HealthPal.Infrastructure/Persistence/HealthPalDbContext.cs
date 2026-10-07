using HealthPal.Domain;
using HealthPal.Domain.Entities;
using HealthPal.Infrastructure.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using System.Text.Json;

namespace HealthPal.Infrastructure.Persistence;

public sealed class HealthPalDbContext : IdentityDbContext<ApplicationUser>
{
    private static readonly JsonSerializerOptions JsonOptions = new();

    public HealthPalDbContext(DbContextOptions<HealthPalDbContext> options)
        : base(options)
    {
    }

    public DbSet<UserProfile> UserProfiles => Set<UserProfile>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<Device> Devices => Set<Device>();
    public DbSet<HourlyHealthBin> HourlyHealthBins => Set<HourlyHealthBin>();
    public DbSet<DailyHealthSummary> DailyHealthSummaries => Set<DailyHealthSummary>();
    public DbSet<ExerciseSession> ExerciseSessions => Set<ExerciseSession>();
    public DbSet<ExerciseCatalogItem> ExerciseCatalogItems => Set<ExerciseCatalogItem>();
    public DbSet<UserExerciseFavorite> UserExerciseFavorites => Set<UserExerciseFavorite>();
    public DbSet<FatigueAssessment> FatigueAssessments => Set<FatigueAssessment>();
    public DbSet<SyncBatch> SyncBatches => Set<SyncBatch>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);

        var utcConverter = new ValueConverter<DateTime, DateTime>(
            v => DateTime.SpecifyKind(v, DateTimeKind.Utc),
            v => DateTime.SpecifyKind(v, DateTimeKind.Utc));

        builder.Entity<ApplicationUser>(entity =>
        {
            entity.HasMany<UserProfile>()
                .WithOne()
                .HasForeignKey(p => p.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany<RefreshToken>()
                .WithOne()
                .HasForeignKey(t => t.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany<Device>()
                .WithOne()
                .HasForeignKey(d => d.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany<HourlyHealthBin>()
                .WithOne()
                .HasForeignKey(h => h.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany<DailyHealthSummary>()
                .WithOne()
                .HasForeignKey(d => d.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany<ExerciseSession>()
                .WithOne()
                .HasForeignKey(e => e.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany<UserExerciseFavorite>()
                .WithOne()
                .HasForeignKey(e => e.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany<FatigueAssessment>()
                .WithOne()
                .HasForeignKey(f => f.UserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany<SyncBatch>()
                .WithOne()
                .HasForeignKey(s => s.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        builder.Entity<UserProfile>(entity =>
        {
            entity.ToTable("user_profiles", table =>
            {
                table.HasCheckConstraint(
                    "ck_user_profiles_height",
                    "height_cm IS NULL OR (height_cm >= 50 AND height_cm <= 250)");
                table.HasCheckConstraint(
                    "ck_user_profiles_weight",
                    "weight_kg IS NULL OR (weight_kg >= 20 AND weight_kg <= 400)");
                table.HasCheckConstraint(
                    "ck_user_profiles_daily_step_goal",
                    "daily_step_goal >= 100");
            });
            entity.HasKey(e => e.UserId);
            entity.Property(e => e.DisplayName).HasMaxLength(100).IsRequired();
            entity.Property(e => e.Gender).HasMaxLength(32);
            entity.Property(e => e.Goal).HasMaxLength(64);
            entity.Property(e => e.Timezone).HasMaxLength(64);
            entity.Property(e => e.PreferredSourceId).HasMaxLength(256);
            entity.Property(e => e.RowVersion)
                .HasColumnName("xmin")
                .HasColumnType("xid")
                .ValueGeneratedOnAddOrUpdate()
                .IsConcurrencyToken();
        });

        builder.Entity<RefreshToken>(entity =>
        {
            entity.ToTable("refresh_tokens");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.TokenHash).HasMaxLength(64).IsRequired();
            entity.Property(e => e.DeviceId).HasMaxLength(128).IsRequired();
            entity.Property(e => e.ReplacedByTokenHash).HasMaxLength(64);
            entity.HasIndex(e => e.TokenHash).IsUnique();
            entity.HasIndex(e => new { e.UserId, e.FamilyId });
        });

        builder.Entity<Device>(entity =>
        {
            entity.ToTable("devices");
            entity.HasKey(e => new { e.UserId, e.Id });
            entity.Property(e => e.Id).HasMaxLength(128);
            entity.Property(e => e.Platform).HasMaxLength(32).IsRequired();
            entity.Property(e => e.AppVersion).HasMaxLength(64);
            entity.Property(e => e.ModelVersion).HasMaxLength(64);
            entity.Property(e => e.SourcePreference).HasMaxLength(256);
        });

        builder.Entity<HourlyHealthBin>(entity =>
        {
            entity.ToTable("hourly_health_bins", table =>
            {
                table.HasCheckConstraint("ck_hourly_health_bins_hr_sample_count", "hr_sample_count >= 0");
                table.HasCheckConstraint("ck_hourly_health_bins_steps", "steps IS NULL OR steps >= 0");
                table.HasCheckConstraint("ck_hourly_health_bins_active_calories", "active_calories IS NULL OR active_calories >= 0");
            });
            entity.HasKey(e => e.Id);
            entity.Property(e => e.HourUtc).HasConversion(utcConverter);
            entity.Property(e => e.SourceId).HasMaxLength(256).IsRequired();
            entity.HasIndex(e => new { e.UserId, e.HourUtc, e.SourceId }).IsUnique();
            entity.HasIndex(e => new { e.UserId, e.HourUtc });
        });

        var coverageConverter = new ValueConverter<Dictionary<string, bool>, string>(
            v => JsonSerializer.Serialize(v, JsonOptions),
            v => JsonSerializer.Deserialize<Dictionary<string, bool>>(v, JsonOptions) ?? new Dictionary<string, bool>());
        var coverageComparer = new ValueComparer<Dictionary<string, bool>>(
            (left, right) => JsonSerializer.Serialize(left, JsonOptions) == JsonSerializer.Serialize(right, JsonOptions),
            v => v == null ? 0 : JsonSerializer.Serialize(v, JsonOptions).GetHashCode(StringComparison.Ordinal),
            v => JsonSerializer.Deserialize<Dictionary<string, bool>>(JsonSerializer.Serialize(v, JsonOptions), JsonOptions) ?? new Dictionary<string, bool>());

        builder.Entity<DailyHealthSummary>(entity =>
        {
            entity.ToTable("daily_health_summaries", table =>
            {
                table.HasCheckConstraint("ck_daily_health_summaries_sleep", "sleep_minutes IS NULL OR sleep_minutes >= 0");
                table.HasCheckConstraint("ck_daily_health_summaries_steps", "steps IS NULL OR steps >= 0");
                table.HasCheckConstraint("ck_daily_health_summaries_active_calories", "active_calories IS NULL OR active_calories >= 0");
                table.HasCheckConstraint("ck_daily_health_summaries_exercise_count", "exercise_count >= 0");
                table.HasCheckConstraint("ck_daily_health_summaries_exercise_duration", "exercise_duration_minutes >= 0");
            });
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Timezone).HasMaxLength(64).IsRequired();
            entity.Property(e => e.CoverageFlags)
                .HasColumnType("jsonb")
                .HasConversion(coverageConverter)
                .Metadata.SetValueComparer(coverageComparer);
            entity.HasIndex(e => new { e.UserId, e.LocalDate }).IsUnique();
        });

        builder.Entity<ExerciseSession>(entity =>
        {
            entity.ToTable("exercise_sessions", table =>
            {
                table.HasCheckConstraint("ck_exercise_sessions_duration", "duration_minutes >= 0");
                table.HasCheckConstraint("ck_exercise_sessions_calories", "calories IS NULL OR calories >= 0");
                table.HasCheckConstraint("ck_exercise_sessions_range", "end_utc >= start_utc");
            });
            entity.HasKey(e => e.Id);
            entity.Property(e => e.ExternalRecordId).HasMaxLength(256).IsRequired();
            entity.Property(e => e.Type).HasMaxLength(128).IsRequired();
            entity.Property(e => e.SourceId).HasMaxLength(256).IsRequired();
            entity.Property(e => e.StartUtc).HasConversion(utcConverter);
            entity.Property(e => e.EndUtc).HasConversion(utcConverter);
            entity.HasIndex(e => new { e.UserId, e.ExternalRecordId }).IsUnique();
            entity.HasIndex(e => new { e.UserId, e.StartUtc });
        });

        builder.Entity<ExerciseCatalogItem>(entity =>
        {
            entity.ToTable("exercise_catalog_items");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasMaxLength(64);
            entity.Property(e => e.Name).HasMaxLength(160).IsRequired();
            entity.Property(e => e.EnglishName).HasMaxLength(160);
            entity.Property(e => e.MuscleGroup).HasMaxLength(32).IsRequired();
            entity.Property(e => e.ExerciseType).HasMaxLength(64).IsRequired();
            entity.Property(e => e.Equipment).HasMaxLength(128).IsRequired();
            entity.Property(e => e.Instructions).HasMaxLength(4000).IsRequired();
            entity.HasIndex(e => new { e.IsActive, e.MuscleGroup });
            entity.HasData(
                new ExerciseCatalogItem { Id = "push-up", Name = "Hít đất", EnglishName = "Push-up", MuscleGroup = "chest", ExerciseType = "Strength", Equipment = "Không dụng cụ", Instructions = "Giữ thân người thẳng, hạ ngực có kiểm soát rồi đẩy trở lại.", IsActive = true },
                new ExerciseCatalogItem { Id = "bodyweight-squat", Name = "Squat không tạ", EnglishName = "Bodyweight Squat", MuscleGroup = "legs", ExerciseType = "Strength", Equipment = "Không dụng cụ", Instructions = "Đẩy hông ra sau, hạ người đến mức thoải mái rồi đứng lên bằng lực chân.", IsActive = true },
                new ExerciseCatalogItem { Id = "reverse-lunge", Name = "Chùng chân ngược", EnglishName = "Reverse Lunge", MuscleGroup = "legs", ExerciseType = "Strength", Equipment = "Không dụng cụ", Instructions = "Bước một chân ra sau, hạ gối có kiểm soát và giữ thân người ổn định.", IsActive = true },
                new ExerciseCatalogItem { Id = "plank", Name = "Plank", EnglishName = "Plank", MuscleGroup = "core", ExerciseType = "Isometric", Equipment = "Không dụng cụ", Instructions = "Siết cơ bụng, giữ đầu-cổ-lưng-hông trên một đường thẳng.", IsActive = true },
                new ExerciseCatalogItem { Id = "band-row", Name = "Kéo dây kháng lực", EnglishName = "Resistance Band Row", MuscleGroup = "back", ExerciseType = "Strength", Equipment = "Dây kháng lực", Instructions = "Kéo khuỷu tay về sau, siết bả vai rồi trả dây chậm.", IsActive = true },
                new ExerciseCatalogItem { Id = "shoulder-press", Name = "Đẩy vai", EnglishName = "Shoulder Press", MuscleGroup = "shoulder", ExerciseType = "Strength", Equipment = "Tạ tay", Instructions = "Đẩy tạ lên trên đầu, không khóa cứng khuỷu tay và hạ xuống có kiểm soát.", IsActive = true },
                new ExerciseCatalogItem { Id = "bicep-curl", Name = "Cuốn tay trước", EnglishName = "Bicep Curl", MuscleGroup = "arms", ExerciseType = "Strength", Equipment = "Tạ tay", Instructions = "Giữ khuỷu tay sát thân, cuốn tạ lên rồi hạ chậm.", IsActive = true },
                new ExerciseCatalogItem { Id = "brisk-walk", Name = "Đi bộ nhanh", EnglishName = "Brisk Walk", MuscleGroup = "cardio", ExerciseType = "Cardio", Equipment = "Không dụng cụ", Instructions = "Đi với tốc độ nhanh vừa đủ để nhịp tim tăng nhưng vẫn nói được câu ngắn.", IsActive = true });
        });

        builder.Entity<UserExerciseFavorite>(entity =>
        {
            entity.ToTable("user_exercise_favorites");
            entity.HasKey(e => new { e.UserId, e.ExerciseId });
            entity.Property(e => e.UserId).HasMaxLength(450);
            entity.Property(e => e.ExerciseId).HasMaxLength(64);
            entity.Property(e => e.CreatedAtUtc).HasConversion(utcConverter);
            entity.HasOne<ExerciseCatalogItem>()
                .WithMany()
                .HasForeignKey(e => e.ExerciseId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        var missingReasonsConverter = new ValueConverter<List<string>, string>(
            v => JsonSerializer.Serialize(v, JsonOptions),
            v => JsonSerializer.Deserialize<List<string>>(v, JsonOptions) ?? new List<string>());
        var missingReasonsComparer = new ValueComparer<List<string>>(
            (left, right) => (left ?? new List<string>()).SequenceEqual(right ?? new List<string>()),
            v => v.Aggregate(0, static (hash, item) => HashCode.Combine(hash, item)),
            v => v.ToList());

        builder.Entity<FatigueAssessment>(entity =>
        {
            entity.ToTable("fatigue_assessments", table =>
            {
                table.HasCheckConstraint(
                    "ck_fatigue_assessments_base_probability",
                    "base_probability IS NULL OR (base_probability >= 0 AND base_probability <= 1)");
                table.HasCheckConstraint(
                    "ck_fatigue_assessments_calibrated_probability",
                    "calibrated_probability IS NULL OR (calibrated_probability >= 0 AND calibrated_probability <= 1)");
                table.HasCheckConstraint(
                    "ck_fatigue_assessments_threshold",
                    "threshold >= 0 AND threshold <= 1");
                table.HasCheckConstraint("ck_fatigue_assessments_coverage_hours", "coverage_hours >= 0");
                table.HasCheckConstraint(
                    "ck_fatigue_assessments_freshness",
                    "data_freshness_minutes IS NULL OR data_freshness_minutes >= 0");
            });
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Id).HasMaxLength(64);
            entity.Property(e => e.ModelVersion).HasMaxLength(64).IsRequired();
            entity.Property(e => e.FeatureVectorHash).HasMaxLength(128).IsRequired();
            entity.Property(e => e.EvaluatedAtUtc).HasConversion(utcConverter);
            entity.Property(e => e.LatestSampleAtUtc).HasConversion(utcConverter);
            entity.Property(e => e.Status).HasConversion<string>().HasMaxLength(64);
            entity.Property(e => e.CreatedBy).HasConversion<string>().HasMaxLength(32);
            entity.Property(e => e.MissingReasons)
                .HasColumnType("jsonb")
                .HasConversion(missingReasonsConverter)
                .Metadata.SetValueComparer(missingReasonsComparer);
            entity.HasIndex(e => new { e.UserId, e.EvaluatedAtUtc, e.ModelVersion }).IsUnique();
            entity.HasIndex(e => new { e.UserId, e.LocalDate, e.EvaluatedAtUtc });
        });

        builder.Entity<SyncBatch>(entity =>
        {
            entity.ToTable("sync_batches");
            entity.HasKey(e => e.Id);
            entity.Property(e => e.DeviceId).HasMaxLength(128).IsRequired();
            entity.Property(e => e.IdempotencyKey).HasMaxLength(128).IsRequired();
            entity.Property(e => e.PayloadHash).HasMaxLength(64).IsRequired();
            entity.Property(e => e.ResultJson).HasColumnType("jsonb").IsRequired();
            entity.Property(e => e.GeneratedAtUtc).HasConversion(utcConverter);
            entity.Property(e => e.Status).HasConversion<string>().HasMaxLength(32);
            entity.HasIndex(e => new { e.UserId, e.DeviceId, e.IdempotencyKey }).IsUnique();
        });
    }
}
