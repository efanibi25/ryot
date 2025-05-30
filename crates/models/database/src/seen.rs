//! `SeaORM` Entity. Generated by sea-orm-codegen 0.11.2

use async_graphql::SimpleObject;
use async_trait::async_trait;
use chrono::{NaiveDate, Utc};
use educe::Educe;
use enum_models::{EntityLot, SeenState};
use media_models::{
    SeenAnimeExtraInformation, SeenMangaExtraInformation, SeenPodcastExtraInformation,
    SeenShowExtraInformation,
};
use nanoid::nanoid;
use rust_decimal::Decimal;
use rust_decimal_macros::dec;
use sea_orm::{ActiveValue, entity::prelude::*};
use serde::{Deserialize, Serialize};

use super::functions::associate_user_with_entity;

#[derive(Clone, PartialEq, DeriveEntityModel, Eq, Serialize, Deserialize, SimpleObject, Educe)]
#[graphql(name = "Seen")]
#[sea_orm(table_name = "seen")]
#[educe(Debug)]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub id: String,
    pub progress: Decimal,
    pub started_on: Option<NaiveDate>,
    pub finished_on: Option<NaiveDate>,
    pub user_id: String,
    pub metadata_id: String,
    pub state: SeenState,
    pub provider_watched_on: Option<String>,
    #[graphql(skip)]
    #[serde(skip)]
    #[educe(Debug(ignore))]
    pub updated_at: Vec<DateTimeUtc>,
    pub show_extra_information: Option<SeenShowExtraInformation>,
    pub podcast_extra_information: Option<SeenPodcastExtraInformation>,
    pub anime_extra_information: Option<SeenAnimeExtraInformation>,
    pub manga_extra_information: Option<SeenMangaExtraInformation>,
    pub manual_time_spent: Option<Decimal>,
    // Generated columns
    pub last_updated_on: DateTimeUtc,
    pub num_times_updated: i32,
    pub review_id: Option<String>,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(
        belongs_to = "super::metadata::Entity",
        from = "Column::MetadataId",
        to = "super::metadata::Column::Id",
        on_update = "Cascade",
        on_delete = "Cascade"
    )]
    Metadata,
    #[sea_orm(
        belongs_to = "super::review::Entity",
        from = "Column::ReviewId",
        to = "super::review::Column::Id",
        on_update = "Cascade",
        on_delete = "SetNull"
    )]
    Review,
    #[sea_orm(
        belongs_to = "super::user::Entity",
        from = "Column::UserId",
        to = "super::user::Column::Id",
        on_update = "Cascade",
        on_delete = "Cascade"
    )]
    User,
}

impl Related<super::metadata::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Metadata.def()
    }
}

impl Related<super::review::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Review.def()
    }
}

impl Related<super::user::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::User.def()
    }
}

#[async_trait]
impl ActiveModelBehavior for ActiveModel {
    async fn before_save<C>(mut self, _db: &C, insert: bool) -> Result<Self, DbErr>
    where
        C: ConnectionTrait,
    {
        let state = self.state.clone().unwrap();
        let progress = self.progress.clone().unwrap();
        let finished_on = self.finished_on.clone().unwrap();
        let started_on = self.started_on.clone().unwrap();
        if progress == dec!(100) && state == SeenState::InProgress {
            self.state = ActiveValue::Set(SeenState::Completed);
            if finished_on.is_none() && started_on.is_some() {
                self.finished_on = ActiveValue::Set(Some(Utc::now().date_naive()));
            }
        }
        if insert {
            self.id = ActiveValue::Set(format!("see_{}", nanoid!(12)));
        }
        Ok(self)
    }

    async fn after_save<C>(model: Model, db: &C, insert: bool) -> Result<Model, DbErr>
    where
        C: ConnectionTrait,
    {
        if insert {
            associate_user_with_entity(db, &model.user_id, &model.metadata_id, EntityLot::Metadata)
                .await
                .ok();
        }
        Ok(model)
    }
}
